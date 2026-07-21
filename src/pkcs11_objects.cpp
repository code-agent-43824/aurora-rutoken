#include "pkcs11_objects.h"
#include "pkcs11_minimal.h"

#include <QtCore/QByteArray>
#include <QtCore/QDateTime>
#include <QtCore/QVariantMap>
#include <QtCore/QVector>
#include <QtNetwork/QSslCertificate>

namespace {

const QString kSource = QStringLiteral("PKCS#11");

// Прочитать байтовый атрибут двухпроходно (сначала длина, потом значение).
QByteArray readByteAttr(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE session,
                        CK_OBJECT_HANDLE obj, CK_ATTRIBUTE_TYPE type)
{
    CK_ATTRIBUTE attr;
    attr.type = type;
    attr.pValue = nullptr;
    attr.ulValueLen = 0;
    if (fns->C_GetAttributeValue(session, obj, &attr, 1) != CKR_OK)
        return QByteArray();
    if (attr.ulValueLen == CK_UNAVAILABLE_INFORMATION || attr.ulValueLen == 0)
        return QByteArray();

    QByteArray buffer(static_cast<int>(attr.ulValueLen), '\0');
    attr.pValue = buffer.data();
    if (fns->C_GetAttributeValue(session, obj, &attr, 1) != CKR_OK)
        return QByteArray();
    return buffer;
}

bool readUlongAttr(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE session,
                   CK_OBJECT_HANDLE obj, CK_ATTRIBUTE_TYPE type, CK_ULONG &out)
{
    CK_ATTRIBUTE attr;
    attr.type = type;
    attr.pValue = &out;
    attr.ulValueLen = sizeof(out);
    return fns->C_GetAttributeValue(session, obj, &attr, 1) == CKR_OK
            && attr.ulValueLen == sizeof(out);
}

QVector<CK_OBJECT_HANDLE> findByClass(CK_FUNCTION_LIST_PREFIX *fns,
                                      CK_SESSION_HANDLE session, CK_OBJECT_CLASS cls)
{
    QVector<CK_OBJECT_HANDLE> result;
    CK_ATTRIBUTE tmpl;
    tmpl.type = CKA_CLASS;
    tmpl.pValue = &cls;
    tmpl.ulValueLen = sizeof(cls);
    if (fns->C_FindObjectsInit(session, &tmpl, 1) != CKR_OK)
        return result;

    CK_OBJECT_HANDLE batch[32];
    CK_ULONG found = 0;
    while (fns->C_FindObjects(session, batch, 32, &found) == CKR_OK && found > 0) {
        for (CK_ULONG i = 0; i < found; ++i)
            result.append(batch[i]);
        if (found < 32)
            break;
    }
    fns->C_FindObjectsFinal(session);
    return result;
}

QString keyTypeName(CK_ULONG keyType)
{
    switch (keyType) {
    case CKK_RSA: return QStringLiteral("RSA");
    case CKK_EC: return QStringLiteral("EC");
    case CKK_GOSTR3410: return QStringLiteral("ГОСТ Р 34.10-2012 (256)");
    case CKK_GOSTR3410_512: return QStringLiteral("ГОСТ Р 34.10-2012 (512)");
    default: return QStringLiteral("тип 0x%1").arg(static_cast<qulonglong>(keyType), 0, 16);
    }
}

QString labelOf(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE session, CK_OBJECT_HANDLE obj)
{
    return QString::fromUtf8(readByteAttr(fns, session, obj, CKA_LABEL));
}

// CKA_ID для точного сопоставления сертификата и ключа (всегда hex).
QString idHexOf(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE session, CK_OBJECT_HANDLE obj)
{
    return QString::fromLatin1(readByteAttr(fns, session, obj, CKA_ID).toHex());
}

// CKA_ID для показа: если первые (до) 3 байта — печатные ASCII, считаем его
// текстовым и выводим целиком как текст, заменяя любые непечатные байты на «.»;
// иначе — hex. По просьбе владельца (часто CKA_ID у Рутокена текстовый).
QString displayId(const QByteArray &id)
{
    if (id.isEmpty())
        return QString();
    const int probe = qMin(3, id.size());
    for (int i = 0; i < probe; ++i) {
        const unsigned char c = static_cast<unsigned char>(id.at(i));
        if (c < 0x20 || c > 0x7e)
            return QString::fromLatin1(id.toHex());
    }
    QString text;
    text.reserve(id.size());
    for (int i = 0; i < id.size(); ++i) {
        const unsigned char c = static_cast<unsigned char>(id.at(i));
        const bool printable = (c >= 0x20 && c <= 0x7e);
        text.append(QChar(static_cast<ushort>(printable ? c : '.')));
    }
    return text;
}

QString idDisplayOf(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE session, CK_OBJECT_HANDLE obj)
{
    return displayId(readByteAttr(fns, session, obj, CKA_ID));
}

QString firstInfo(const QStringList &values)
{
    return values.isEmpty() ? QString() : values.first();
}

// Разобрать тело сертификата (DER X.509) и заполнить commonName/issuer/expiry.
// Возвращает true, если удалось извлечь хоть одно поле (иначе — fallback на
// CKA_LABEL на стороне вызывающего; например, для ГОСТ без поддержки в OpenSSL).
bool parseCertificate(const QByteArray &der, QString &commonName, QString &issuer,
                      QString &expiry)
{
    if (der.isEmpty())
        return false;
    const QSslCertificate cert(der, QSsl::Der);
    if (cert.isNull())
        return false;

    commonName = firstInfo(cert.subjectInfo(QSslCertificate::CommonName));
    issuer = firstInfo(cert.issuerInfo(QSslCertificate::CommonName));
    if (issuer.isEmpty())
        issuer = firstInfo(cert.issuerInfo(QSslCertificate::Organization));

    const QDateTime notAfter = cert.expiryDate();
    if (notAfter.isValid())
        expiry = notAfter.toUTC().toString(QStringLiteral("yyyy-MM-dd"));

    return !commonName.isEmpty() || !issuer.isEmpty() || notAfter.isValid();
}

QVariantMap makeKey(const QString &idHex, const QString &idText, const QString &label,
                    const QString &keyType, CK_OBJECT_CLASS cls)
{
    QVariantMap key;
    key.insert(QStringLiteral("idHex"), idHex);
    key.insert(QStringLiteral("idText"), idText);
    key.insert(QStringLiteral("label"), label);
    key.insert(QStringLiteral("keyType"), keyType);
    key.insert(QStringLiteral("keyClass"),
               cls == CKO_PRIVATE_KEY ? QStringLiteral("закрытый ключ")
                                      : QStringLiteral("открытый ключ"));
    key.insert(QStringLiteral("source"), kSource);
    return key;
}

} // namespace

namespace pkcs11 {

QVariantList listTokenObjects(CK_FUNCTION_LIST_PREFIX *fns, unsigned long sessionHandle, bool loggedIn)
{
    QVariantList out;
    if (!fns || !fns->C_FindObjectsInit || !fns->C_FindObjects || !fns->C_FindObjectsFinal
            || !fns->C_GetAttributeValue)
        return out;

    const CK_SESSION_HANDLE session = static_cast<CK_SESSION_HANDLE>(sessionHandle);

    // Ключи читаем только в залогиненной сессии: приватные ключи не видны без
    // входа, а до входа наличие ключа у сертификата неизвестно.
    struct KeyEntry { QString idHex; QVariantMap map; bool consumed; };
    QVector<KeyEntry> keys;
    if (loggedIn) {
        const CK_OBJECT_CLASS keyClasses[2] = { CKO_PRIVATE_KEY, CKO_PUBLIC_KEY };
        for (int k = 0; k < 2; ++k) {
            const QVector<CK_OBJECT_HANDLE> handles = findByClass(fns, session, keyClasses[k]);
            for (int i = 0; i < handles.size(); ++i) {
                const CK_OBJECT_HANDLE obj = handles.at(i);
                const QString idHex = idHexOf(fns, session, obj);
                const QString idText = idDisplayOf(fns, session, obj);
                const QString label = labelOf(fns, session, obj);
                CK_ULONG keyType = 0;
                const QString keyTypeStr = readUlongAttr(fns, session, obj, CKA_KEY_TYPE, keyType)
                        ? keyTypeName(keyType) : QString();
                KeyEntry entry;
                entry.idHex = idHex;
                entry.map = makeKey(idHex, idText, label, keyTypeStr, keyClasses[k]);
                entry.consumed = false;
                keys.append(entry);
            }
        }
    }

    // Сертификаты — верхний уровень. Описание берём из разобранного тела X.509
    // (Common Name / Issuer / срок истечения), fallback — CKA_LABEL.
    const QVector<CK_OBJECT_HANDLE> certs = findByClass(fns, session, CKO_CERTIFICATE);
    for (int i = 0; i < certs.size(); ++i) {
        const CK_OBJECT_HANDLE obj = certs.at(i);
        const QString idHex = idHexOf(fns, session, obj);
        const QString idText = idDisplayOf(fns, session, obj);
        const QString label = labelOf(fns, session, obj);

        const QByteArray der = readByteAttr(fns, session, obj, CKA_VALUE);
        QString commonName, issuer, expiry;
        const bool parsed = parseCertificate(der, commonName, issuer, expiry);

        QVariantList certKeys;
        if (loggedIn && !idHex.isEmpty()) {
            for (int j = 0; j < keys.size(); ++j) {
                if (!keys[j].consumed && keys[j].idHex == idHex) {
                    keys[j].consumed = true;
                    certKeys.append(keys[j].map);
                }
            }
        }

        QVariantMap cert;
        cert.insert(QStringLiteral("kind"), QStringLiteral("certificate"));
        cert.insert(QStringLiteral("commonName"), commonName);
        cert.insert(QStringLiteral("issuer"), issuer);
        cert.insert(QStringLiteral("expiry"), expiry);
        cert.insert(QStringLiteral("parsed"), parsed);
        cert.insert(QStringLiteral("idHex"), idHex);
        cert.insert(QStringLiteral("idText"), idText);
        cert.insert(QStringLiteral("label"), label);
        cert.insert(QStringLiteral("derB64"), QString::fromLatin1(der.toBase64())); // для экспорта
        cert.insert(QStringLiteral("source"), kSource);
        cert.insert(QStringLiteral("keysKnown"), loggedIn);
        cert.insert(QStringLiteral("hasKey"), !certKeys.isEmpty());
        cert.insert(QStringLiteral("keys"), certKeys);
        out.append(cert);
    }

    // Ключи без сертификата — на верхний уровень (только когда вошли).
    for (int j = 0; j < keys.size(); ++j) {
        if (keys[j].consumed)
            continue;
        QVariantMap orphan = keys[j].map;
        orphan.insert(QStringLiteral("kind"), QStringLiteral("key"));
        out.append(orphan);
    }

    return out;
}

} // namespace pkcs11
