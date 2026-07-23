#include "pkcs11_certimport.h"
#include "pkcs11_errors.h"
#include "pkcs11_minimal.h"

#include <QtCore/QByteArray>
#include <QtCore/QCryptographicHash>
#include <QtCore/QFile>
#include <QtCore/QStringList>
#include <QtCore/QUrl>
#include <QtCore/QVector>
#include <QtNetwork/QSslCertificate>

namespace {

// --- Минимальный разбор DER (TLV) ------------------------------------------
// Логика проверена на реальном сертификате (сверка смещений и RSA-modulus с
// openssl asn1parse): serial/issuer/subject/SubjectPublicKeyInfo извлекаются
// точно. Раскладка TBSCertificate одинакова для ГОСТ и RSA; различается только
// нормализация самого открытого ключа (ниже).
struct Tlv {
    quint8 tag = 0;
    int hdrLen = 0;
    int len = 0;
    int contentPos = 0;
    bool ok = false;
};

Tlv readTlv(const QByteArray &d, int pos)
{
    Tlv t;
    if (pos < 0 || pos + 2 > d.size())
        return t;
    t.tag = static_cast<quint8>(d.at(pos));
    int p = pos + 1;
    int first = static_cast<quint8>(d.at(p));
    ++p;
    if (first < 0x80) {
        t.len = first;
    } else {
        const int n = first & 0x7f;
        if (n == 0 || n > 4 || p + n > d.size())
            return t; // неопределённая/слишком длинная форма не поддерживается
        int len = 0;
        for (int i = 0; i < n; ++i) {
            len = (len << 8) | static_cast<quint8>(d.at(p));
            ++p;
        }
        t.len = len;
    }
    t.contentPos = p;
    t.hdrLen = p - pos;
    if (t.contentPos + t.len > d.size())
        return t;
    t.ok = true;
    return t;
}

int endOf(const Tlv &t) { return t.contentPos + t.len; }

struct CertFields {
    QByteArray der;
    QByteArray subject;
    QByteArray issuer;
    QByteArray serial;
    QByteArray spkiPublicKey; // содержимое subjectPublicKey BIT STRING без байта unused-bits
    bool valid = false;
};

bool parseCertFields(const QByteArray &der, CertFields &out)
{
    out = CertFields();
    out.der = der;

    Tlv cert = readTlv(der, 0);
    if (!cert.ok || cert.tag != 0x30)
        return false; // Certificate SEQUENCE
    Tlv tbs = readTlv(der, cert.contentPos);
    if (!tbs.ok || tbs.tag != 0x30)
        return false; // TBSCertificate SEQUENCE

    int p = tbs.contentPos;
    Tlv f = readTlv(der, p);
    if (!f.ok)
        return false;
    if (f.tag == 0xA0) { // необязательный version [0]
        p = endOf(f);
        f = readTlv(der, p);
        if (!f.ok)
            return false;
    }
    if (f.tag != 0x02)
        return false; // serialNumber INTEGER
    out.serial = der.mid(p, f.hdrLen + f.len);
    p = endOf(f);

    f = readTlv(der, p);
    if (!f.ok || f.tag != 0x30)
        return false; // signature AlgorithmIdentifier (пропускаем)
    p = endOf(f);

    f = readTlv(der, p);
    if (!f.ok || f.tag != 0x30)
        return false; // issuer Name
    out.issuer = der.mid(p, f.hdrLen + f.len);
    p = endOf(f);

    f = readTlv(der, p);
    if (!f.ok || f.tag != 0x30)
        return false; // validity (пропускаем)
    p = endOf(f);

    f = readTlv(der, p);
    if (!f.ok || f.tag != 0x30)
        return false; // subject Name
    out.subject = der.mid(p, f.hdrLen + f.len);
    p = endOf(f);

    Tlv spki = readTlv(der, p);
    if (!spki.ok || spki.tag != 0x30)
        return false; // SubjectPublicKeyInfo
    Tlv alg = readTlv(der, spki.contentPos);
    if (!alg.ok || alg.tag != 0x30)
        return false; // algorithm
    Tlv bits = readTlv(der, endOf(alg));
    if (!bits.ok || bits.tag != 0x03 || bits.len < 1)
        return false; // subjectPublicKey BIT STRING
    out.spkiPublicKey = der.mid(bits.contentPos + 1, bits.len - 1); // без байта unused-bits

    out.valid = true;
    return true;
}

// Если байты — единственный DER OCTET STRING, вернуть его содержимое; иначе как есть.
QByteArray unwrapOctetString(const QByteArray &d)
{
    Tlv t = readTlv(d, 0);
    if (t.ok && t.tag == 0x04 && t.hdrLen + t.len == d.size())
        return d.mid(t.contentPos, t.len);
    return d;
}

QByteArray stripLeadingZeros(QByteArray m)
{
    while (m.size() > 1 && static_cast<quint8>(m.at(0)) == 0x00)
        m.remove(0, 1);
    return m;
}

// RSA modulus из subjectPublicKey SEQUENCE { INTEGER modulus, INTEGER exponent }.
QByteArray rsaModulusFromSpk(const QByteArray &spk)
{
    Tlv seq = readTlv(spk, 0);
    if (!seq.ok || seq.tag != 0x30)
        return QByteArray();
    Tlv modInt = readTlv(spk, seq.contentPos);
    if (!modInt.ok || modInt.tag != 0x02)
        return QByteArray();
    return stripLeadingZeros(spk.mid(modInt.contentPos, modInt.len));
}

QByteArray reversedBytes(const QByteArray &a)
{
    QByteArray r(a.size(), '\0');
    for (int i = 0; i < a.size(); ++i)
        r[i] = a.at(a.size() - 1 - i);
    return r;
}

// --- Чтение атрибутов токена -----------------------------------------------
QByteArray readByteAttr(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE s,
                        CK_OBJECT_HANDLE o, CK_ATTRIBUTE_TYPE type)
{
    CK_ATTRIBUTE a;
    a.type = type;
    a.pValue = nullptr;
    a.ulValueLen = 0;
    if (fns->C_GetAttributeValue(s, o, &a, 1) != CKR_OK)
        return QByteArray();
    if (a.ulValueLen == CK_UNAVAILABLE_INFORMATION || a.ulValueLen == 0)
        return QByteArray();
    QByteArray buf(static_cast<int>(a.ulValueLen), '\0');
    a.pValue = buf.data();
    if (fns->C_GetAttributeValue(s, o, &a, 1) != CKR_OK)
        return QByteArray();
    return buf;
}

QVector<CK_OBJECT_HANDLE> findPublicKeys(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE s)
{
    QVector<CK_OBJECT_HANDLE> r;
    CK_OBJECT_CLASS cls = CKO_PUBLIC_KEY;
    CK_ATTRIBUTE tmpl;
    tmpl.type = CKA_CLASS;
    tmpl.pValue = &cls;
    tmpl.ulValueLen = sizeof(cls);
    if (fns->C_FindObjectsInit(s, &tmpl, 1) != CKR_OK)
        return r;
    CK_OBJECT_HANDLE batch[32];
    CK_ULONG found = 0;
    while (fns->C_FindObjects(s, batch, 32, &found) == CKR_OK && found > 0) {
        for (CK_ULONG i = 0; i < found; ++i)
            r.append(batch[i]);
        if (found < 32)
            break;
    }
    fns->C_FindObjectsFinal(s);
    return r;
}

// Ищем на токене открытый ключ, совпадающий с ключом сертификата; возвращаем его
// CKA_ID (пустой — если не найден). Для RSA сравниваем modulus; для ГОСТ —
// CKA_VALUE (распакованный) в прямом и обратном порядке байт (порядок координат
// у ГОСТ между сертификатом и токеном может различаться).
QByteArray matchKeyId(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE s, const CertFields &cf)
{
    const QByteArray certGost = unwrapOctetString(cf.spkiPublicKey);
    const QByteArray certGostRev = reversedBytes(certGost);
    const QByteArray certRsaMod = rsaModulusFromSpk(cf.spkiPublicKey);

    const QVector<CK_OBJECT_HANDLE> pubs = findPublicKeys(fns, s);
    for (int i = 0; i < pubs.size(); ++i) {
        const CK_OBJECT_HANDLE o = pubs.at(i);
        CK_ULONG kt = 0;
        CK_ATTRIBUTE a;
        a.type = CKA_KEY_TYPE;
        a.pValue = &kt;
        a.ulValueLen = sizeof(kt);
        const bool haveKt = (fns->C_GetAttributeValue(s, o, &a, 1) == CKR_OK && a.ulValueLen == sizeof(kt));

        if (haveKt && kt == CKK_RSA) {
            if (!certRsaMod.isEmpty()) {
                const QByteArray mod = stripLeadingZeros(readByteAttr(fns, s, o, CKA_MODULUS));
                if (!mod.isEmpty() && mod == certRsaMod)
                    return readByteAttr(fns, s, o, CKA_ID);
            }
        } else if (!certGost.isEmpty()) {
            const QByteArray val = unwrapOctetString(readByteAttr(fns, s, o, CKA_VALUE));
            if (!val.isEmpty() && (val == certGost || val == certGostRev))
                return readByteAttr(fns, s, o, CKA_ID);
        }
    }
    return QByteArray();
}

// Прочитать файл и вернуть DER: PEM декодируется из base64, сырой DER — как есть.
QByteArray readCertDer(const QString &filePath, QString &err)
{
    QString path = filePath;
    if (path.startsWith(QStringLiteral("file://")))
        path = QUrl(path).toLocalFile();

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        err = QStringLiteral("Не удалось открыть файл: ") + path;
        return QByteArray();
    }
    const QByteArray raw = file.readAll();
    file.close();
    if (raw.isEmpty()) {
        err = QStringLiteral("Файл пуст");
        return QByteArray();
    }

    const QByteArray beginMark = "-----BEGIN CERTIFICATE-----";
    const int b = raw.indexOf(beginMark);
    if (b >= 0) {
        const int e = raw.indexOf("-----END CERTIFICATE-----", b);
        if (e < 0) {
            err = QStringLiteral("Повреждённый PEM (нет END)");
            return QByteArray();
        }
        QByteArray body = raw.mid(b + beginMark.size(), e - (b + beginMark.size()));
        body.replace('\r', "").replace('\n', "").replace(' ', "").replace('\t', "");
        const QByteArray der = QByteArray::fromBase64(body);
        if (der.isEmpty()) {
            err = QStringLiteral("Не удалось декодировать PEM");
            return QByteArray();
        }
        return der;
    }
    return raw; // сырой DER
}

} // namespace

namespace pkcs11 {

ImportResult importCertificateFromFile(CK_FUNCTION_LIST_PREFIX *fns, unsigned long sessionHandle,
                                       const QString &filePath, const QString &label)
{
    ImportResult res;
    if (!fns || !fns->C_CreateObject) {
        res.message = QStringLiteral("Библиотека не предоставляет C_CreateObject");
        return res;
    }
    const CK_SESSION_HANDLE session = static_cast<CK_SESSION_HANDLE>(sessionHandle);

    QString err;
    const QByteArray der = readCertDer(filePath, err);
    if (der.isEmpty()) {
        res.message = err;
        return res;
    }

    CertFields cf;
    if (!parseCertFields(der, cf) || cf.subject.isEmpty()) {
        res.message = QStringLiteral("Файл не похож на X.509-сертификат");
        return res;
    }

    // Метка: пользовательская → иначе Common Name из тела → иначе «imported».
    QByteArray labelBytes = label.toUtf8();
    if (labelBytes.isEmpty()) {
        const QSslCertificate qc(der, QSsl::Der);
        const QStringList cns = qc.isNull() ? QStringList()
                                            : qc.subjectInfo(QSslCertificate::CommonName);
        const QString cn = cns.isEmpty() ? QString() : cns.first();
        labelBytes = (cn.isEmpty() ? QStringLiteral("imported certificate") : cn).toUtf8();
    }

    // Приклеивание к паре по открытому ключу; иначе CKA_ID = SHA-1 от ключа.
    QByteArray id = matchKeyId(fns, session, cf);
    const bool attached = !id.isEmpty();
    if (id.isEmpty())
        id = QCryptographicHash::hash(unwrapOctetString(cf.spkiPublicKey), QCryptographicHash::Sha1);

    CK_OBJECT_CLASS cls = CKO_CERTIFICATE;
    CK_CERTIFICATE_TYPE ctype = CKC_X_509;
    CK_BBOOL yes = CK_TRUE_VALUE;
    CK_BBOOL no = 0;

    QVector<CK_ATTRIBUTE> tmpl;
    tmpl.reserve(10);
    const auto add = [&tmpl](CK_ATTRIBUTE_TYPE t, const void *v, CK_ULONG l) {
        CK_ATTRIBUTE a;
        a.type = t;
        a.pValue = const_cast<void *>(v);
        a.ulValueLen = l;
        tmpl.append(a);
    };
    add(CKA_CLASS, &cls, sizeof(cls));
    add(CKA_CERTIFICATE_TYPE, &ctype, sizeof(ctype));
    add(CKA_TOKEN, &yes, sizeof(yes));
    add(CKA_PRIVATE, &no, sizeof(no));
    add(CKA_VALUE, der.constData(), static_cast<CK_ULONG>(der.size()));
    add(CKA_SUBJECT, cf.subject.constData(), static_cast<CK_ULONG>(cf.subject.size()));
    if (!cf.issuer.isEmpty())
        add(CKA_ISSUER, cf.issuer.constData(), static_cast<CK_ULONG>(cf.issuer.size()));
    if (!cf.serial.isEmpty())
        add(CKA_SERIAL_NUMBER, cf.serial.constData(), static_cast<CK_ULONG>(cf.serial.size()));
    add(CKA_ID, id.constData(), static_cast<CK_ULONG>(id.size()));
    add(CKA_LABEL, labelBytes.constData(), static_cast<CK_ULONG>(labelBytes.size()));

    CK_OBJECT_HANDLE obj = 0;
    const CK_RV rv = fns->C_CreateObject(session, tmpl.data(),
                                         static_cast<CK_ULONG>(tmpl.size()), &obj);
    if (rv == CKR_OK) {
        res.ok = true;
        res.attached = attached;
        res.message = attached
                ? QStringLiteral("Сертификат импортирован и привязан к ключевой паре")
                : QStringLiteral("Сертификат импортирован (пара с таким открытым ключом не найдена)");
    } else {
        res.message = QStringLiteral("C_CreateObject: ") + pkcs11::rvMessage(rv);
    }
    return res;
}

} // namespace pkcs11
