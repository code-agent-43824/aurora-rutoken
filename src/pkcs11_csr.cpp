#include "pkcs11_csr.h"
#include "pkcs11_minimal.h"

#include <QtCore/QByteArray>

#include <initializer_list>

namespace {

QString rvHex(CK_RV rv)
{
    return QStringLiteral("0x%1").arg(static_cast<qulonglong>(rv), 8, 16, QLatin1Char('0'));
}

// --- Минимальный DER-энкодер ------------------------------------------------
QByteArray derLen(int n)
{
    QByteArray r;
    if (n < 0x80) {
        r.append(static_cast<char>(n));
        return r;
    }
    QByteArray tmp;
    while (n > 0) {
        tmp.prepend(static_cast<char>(n & 0xff));
        n >>= 8;
    }
    r.append(static_cast<char>(0x80 | tmp.size()));
    r.append(tmp);
    return r;
}

QByteArray tlv(quint8 tag, const QByteArray &content)
{
    QByteArray r;
    r.append(static_cast<char>(tag));
    r.append(derLen(content.size()));
    r.append(content);
    return r;
}

QByteArray seq(const QByteArray &c) { return tlv(0x30, c); }
QByteArray set(const QByteArray &c) { return tlv(0x31, c); }
QByteArray bitString(const QByteArray &c) { return tlv(0x03, QByteArray(1, '\0') + c); } // 0 unused bits
QByteArray octetString(const QByteArray &c) { return tlv(0x04, c); }

// OID из «частей» кодированного значения (байты после тега/длины).
QByteArray oid(std::initializer_list<int> bytes)
{
    QByteArray c;
    for (int b : bytes)
        c.append(static_cast<char>(b & 0xff));
    return tlv(0x06, c);
}

// DER INTEGER из беззнаковых байтов (минимальная форма, ведущий 0x00 при MSB=1).
QByteArray uintInteger(QByteArray v)
{
    while (v.size() > 1 && static_cast<quint8>(v.at(0)) == 0x00)
        v.remove(0, 1);
    if (v.isEmpty())
        v.append('\0');
    if (static_cast<quint8>(v.at(0)) & 0x80)
        v.prepend('\0');
    return tlv(0x02, v);
}

// --- Разбор DER (только для распознавания OCTET STRING в CKA_VALUE) ----------
bool isWholeOctetString(const QByteArray &d)
{
    if (d.size() < 2 || static_cast<quint8>(d.at(0)) != 0x04)
        return false;
    int p = 1;
    int first = static_cast<quint8>(d.at(p++));
    int len;
    if (first < 0x80) {
        len = first;
    } else {
        int n = first & 0x7f;
        if (n == 0 || n > 4 || p + n > d.size())
            return false;
        len = 0;
        for (int i = 0; i < n; ++i)
            len = (len << 8) | static_cast<quint8>(d.at(p++));
    }
    return p + len == d.size();
}

// Гарантировать форму DER OCTET STRING: если уже целиком OCTET STRING — как есть,
// иначе обернуть сырые байты.
QByteArray asOctetString(const QByteArray &v)
{
    return isWholeOctetString(v) ? v : octetString(v);
}

// --- Чтение атрибутов токена -----------------------------------------------
QByteArray readAttr(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE s,
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

// Найти один объект заданного класса с заданным CKA_ID.
CK_OBJECT_HANDLE findByClassAndId(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE s,
                                  CK_OBJECT_CLASS cls, const QByteArray &idBytes)
{
    CK_ATTRIBUTE tmpl[2];
    tmpl[0].type = CKA_CLASS;
    tmpl[0].pValue = &cls;
    tmpl[0].ulValueLen = sizeof(cls);
    tmpl[1].type = CKA_ID;
    tmpl[1].pValue = const_cast<char *>(idBytes.constData());
    tmpl[1].ulValueLen = static_cast<CK_ULONG>(idBytes.size());
    if (fns->C_FindObjectsInit(s, tmpl, 2) != CKR_OK)
        return 0;
    CK_OBJECT_HANDLE h = 0;
    CK_ULONG found = 0;
    fns->C_FindObjects(s, &h, 1, &found);
    fns->C_FindObjectsFinal(s);
    return found > 0 ? h : 0;
}

CK_ULONG readKeyType(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE s, CK_OBJECT_HANDLE o)
{
    CK_ULONG kt = 0;
    CK_ATTRIBUTE a;
    a.type = CKA_KEY_TYPE;
    a.pValue = &kt;
    a.ulValueLen = sizeof(kt);
    if (fns->C_GetAttributeValue(s, o, &a, 1) != CKR_OK || a.ulValueLen != sizeof(kt))
        return static_cast<CK_ULONG>(-1);
    return kt;
}

// --- DN → Name --------------------------------------------------------------
QByteArray rdn(const QByteArray &oidTlv, quint8 strTag, const QString &value)
{
    QByteArray v = (strTag == 0x16) ? value.toLatin1() : value.toUtf8(); // IA5 — латиница
    return set(seq(oidTlv + tlv(strTag, v)));
}

QByteArray buildName(const pkcs11::CsrDn &dn)
{
    QByteArray n;
    if (!dn.commonName.isEmpty())       n += rdn(oid({0x55, 0x04, 0x03}), 0x0C, dn.commonName);
    if (!dn.organization.isEmpty())     n += rdn(oid({0x55, 0x04, 0x0A}), 0x0C, dn.organization);
    if (!dn.organizationUnit.isEmpty()) n += rdn(oid({0x55, 0x04, 0x0B}), 0x0C, dn.organizationUnit);
    if (!dn.country.isEmpty())          n += rdn(oid({0x55, 0x04, 0x06}), 0x13, dn.country); // PrintableString
    if (!dn.locality.isEmpty())         n += rdn(oid({0x55, 0x04, 0x07}), 0x0C, dn.locality);
    if (!dn.state.isEmpty())            n += rdn(oid({0x55, 0x04, 0x08}), 0x0C, dn.state);
    if (!dn.email.isEmpty())            n += rdn(oid({0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x01}),
                                                 0x16, dn.email); // IA5String
    return seq(n);
}

// --- PEM --------------------------------------------------------------------
QString toPem(const QByteArray &der)
{
    const QByteArray b64 = der.toBase64();
    QByteArray p = "-----BEGIN CERTIFICATE REQUEST-----\n";
    for (int i = 0; i < b64.size(); i += 64) {
        p += b64.mid(i, 64);
        p += '\n';
    }
    p += "-----END CERTIFICATE REQUEST-----\n";
    return QString::fromLatin1(p.constData(), p.size());
}

} // namespace

namespace pkcs11 {

CsrResult createCsr(CK_FUNCTION_LIST_PREFIX *fns, unsigned long sessionHandle,
                    const QByteArray &idBytes, const CsrDn &dn)
{
    CsrResult res;
    if (!fns || !fns->C_GetAttributeValue || !fns->C_FindObjectsInit
            || !fns->C_SignInit || !fns->C_Sign) {
        res.message = QStringLiteral("Библиотека не предоставляет функции для запроса");
        return res;
    }
    const CK_SESSION_HANDLE session = static_cast<CK_SESSION_HANDLE>(sessionHandle);
    if (idBytes.isEmpty()) {
        res.message = QStringLiteral("У ключа нет CKA_ID — запрос недоступен");
        return res;
    }

    const CK_OBJECT_HANDLE hPub = findByClassAndId(fns, session, CKO_PUBLIC_KEY, idBytes);
    const CK_OBJECT_HANDLE hPriv = findByClassAndId(fns, session, CKO_PRIVATE_KEY, idBytes);
    if (hPub == 0 || hPriv == 0) {
        res.message = QStringLiteral("Ключевая пара по этому CKA_ID не найдена (нужны открытый и закрытый ключи)");
        return res;
    }

    const CK_ULONG keyType = readKeyType(fns, session, hPub);

    // SubjectPublicKeyInfo и алгоритмы (по типу ключа).
    QByteArray spki;
    QByteArray sigAlg;
    CK_MECHANISM_TYPE mechType = 0;

    if (keyType == CKK_GOSTR3410 || keyType == CKK_GOSTR3410_512) {
        const bool is512 = (keyType == CKK_GOSTR3410_512);
        const QByteArray keyVal = readAttr(fns, session, hPub, CKA_VALUE);
        const QByteArray p3410 = readAttr(fns, session, hPub, CKA_GOSTR3410_PARAMS); // DER OID
        const QByteArray p3411 = readAttr(fns, session, hPub, CKA_GOSTR3411_PARAMS); // DER OID
        if (keyVal.isEmpty() || p3410.isEmpty()) {
            res.message = QStringLiteral("Не удалось прочитать открытый ключ ГОСТ с токена");
            return res;
        }
        // algorithm OID открытого ключа: 1.2.643.7.1.1.1.1 (256) / .1.2 (512).
        const QByteArray algOid = is512
                ? oid({0x2A, 0x85, 0x03, 0x07, 0x01, 0x01, 0x01, 0x02})
                : oid({0x2A, 0x85, 0x03, 0x07, 0x01, 0x01, 0x01, 0x01});
        const QByteArray params = seq(p3410 + p3411); // publicKeyParamSet + digestParamSet
        const QByteArray algId = seq(algOid + params);
        spki = seq(algId + bitString(asOctetString(keyVal)));
        // signatureAlgorithm: id-tc26-signwithdigest-gost3410-12-256/512.
        sigAlg = is512
                ? seq(oid({0x2A, 0x85, 0x03, 0x07, 0x01, 0x01, 0x03, 0x03}))
                : seq(oid({0x2A, 0x85, 0x03, 0x07, 0x01, 0x01, 0x03, 0x02}));
        mechType = is512 ? CKM_GOSTR3410_WITH_GOSTR3411_12_512 : CKM_GOSTR3410_WITH_GOSTR3411_12_256;
    } else if (keyType == CKK_RSA) {
        const QByteArray modulus = readAttr(fns, session, hPub, CKA_MODULUS);
        const QByteArray exponent = readAttr(fns, session, hPub, CKA_PUBLIC_EXPONENT);
        if (modulus.isEmpty() || exponent.isEmpty()) {
            res.message = QStringLiteral("Не удалось прочитать открытый ключ RSA с токена");
            return res;
        }
        const QByteArray rsaOid = oid({0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01});
        const QByteArray algId = seq(rsaOid + QByteArray::fromHex("0500")); // NULL
        const QByteArray rsaPub = seq(uintInteger(modulus) + uintInteger(exponent));
        spki = seq(algId + bitString(rsaPub));
        // sha256WithRSAEncryption 1.2.840.113549.1.1.11.
        sigAlg = seq(oid({0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B})
                     + QByteArray::fromHex("0500"));
        mechType = CKM_SHA256_RSA_PKCS;
    } else {
        res.message = QStringLiteral("Тип ключа не поддерживается для запроса (нужен ГОСТ или RSA)");
        return res;
    }

    // CertificationRequestInfo ::= SEQUENCE { version(0), subject, spki, [0] attributes(пусто) }.
    const QByteArray name = buildName(dn);
    const QByteArray attrs = tlv(0xA0, QByteArray()); // [0] IMPLICIT SET OF Attribute — пусто
    const QByteArray cri = seq(uintInteger(QByteArray(1, '\0')) + name + spki + attrs);

    // Подпись CertificationRequestInfo закрытым ключом на токене.
    CK_MECHANISM mech;
    mech.mechanism = mechType;
    mech.pParameter = nullptr;
    mech.ulParameterLen = 0;
    CK_RV rv = fns->C_SignInit(session, &mech, hPriv);
    if (rv != CKR_OK) {
        res.message = QStringLiteral("C_SignInit: ") + rvHex(rv);
        return res;
    }
    QByteArray criData = cri;
    CK_BYTE *criPtr = reinterpret_cast<CK_BYTE *>(criData.data());
    const CK_ULONG criLen = static_cast<CK_ULONG>(criData.size());
    CK_ULONG sigLen = 0;
    rv = fns->C_Sign(session, criPtr, criLen, nullptr, &sigLen);
    if (rv != CKR_OK) {
        res.message = QStringLiteral("C_Sign(длина): ") + rvHex(rv);
        return res;
    }
    QByteArray signature(static_cast<int>(sigLen), '\0');
    rv = fns->C_Sign(session, criPtr, criLen,
                     reinterpret_cast<CK_BYTE *>(signature.data()), &sigLen);
    if (rv != CKR_OK) {
        res.message = QStringLiteral("C_Sign: ") + rvHex(rv);
        return res;
    }
    signature.truncate(static_cast<int>(sigLen));

    // CertificationRequest ::= SEQUENCE { cri, signatureAlgorithm, signature BIT STRING }.
    const QByteArray csr = seq(cri + sigAlg + bitString(signature));

    res.ok = true;
    res.pem = toPem(csr);
    res.message = QStringLiteral("Запрос на сертификат сформирован");
    return res;
}

} // namespace pkcs11
