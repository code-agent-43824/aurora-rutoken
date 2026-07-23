#include "pkcs11_keygen.h"
#include "pkcs11_minimal.h"

#include <QtCore/QByteArray>
#include <QtCore/QUuid>
#include <QtCore/QVector>

namespace {

QString rvHex(CK_RV rv)
{
    return QStringLiteral("0x%1").arg(static_cast<qulonglong>(rv), 8, 16, QLatin1Char('0'));
}

// DER-кодированные OID параметров ГОСТ (из docs/RESEARCH.md §5в).
// 256: ключ — набор A (OID 1.2.643.2.2.35.1); хеш — 2012-256 (OID 1.2.643.7.1.1.2.2).
const CK_BYTE kGost256KeyParams[]  = { 0x06, 0x07, 0x2A, 0x85, 0x03, 0x02, 0x02, 0x23, 0x01 };
const CK_BYTE kGost256HashParams[] = { 0x06, 0x08, 0x2A, 0x85, 0x03, 0x07, 0x01, 0x01, 0x02, 0x02 };
// 512: ключ — набор A (OID 1.2.643.7.1.2.1.2.1); хеш — 2012-512 (OID 1.2.643.7.1.1.2.3).
const CK_BYTE kGost512KeyParams[]  = { 0x06, 0x09, 0x2A, 0x85, 0x03, 0x07, 0x01, 0x02, 0x01, 0x02, 0x01 };
const CK_BYTE kGost512HashParams[] = { 0x06, 0x08, 0x2A, 0x85, 0x03, 0x07, 0x01, 0x01, 0x02, 0x03 };

void appendAttr(QVector<CK_ATTRIBUTE> &tmpl, CK_ATTRIBUTE_TYPE type, void *value, CK_ULONG len)
{
    CK_ATTRIBUTE a;
    a.type = type;
    a.pValue = value;
    a.ulValueLen = len;
    tmpl.append(a);
}

// Тестовая подпись/проверка сразу после генерации: подписываем фиксированный
// буфер закрытым ключом и проверяем открытым (та же сессия, свежие дескрипторы).
// Механизм и длина данных — по типу ключа: ГОСТ 2012-256 → CKM_GOSTR3410, 32
// байта; ГОСТ 2012-512 → CKM_GOSTR3410_512, 64 байта («сырые» механизмы требуют
// блок ровно размером с хеш); RSA → CKM_RSA_PKCS, короткий блок. Возвращает
// суффикс к сообщению о генерации. Любая ошибка (нет функций, неверный механизм,
// не та длина) деградирует мягко — сообщение с кодом, без краша.
QString testSignVerify(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE session,
                       CK_OBJECT_HANDLE hPriv, CK_OBJECT_HANDLE hPub, CK_KEY_TYPE keyType)
{
    if (!fns->C_SignInit || !fns->C_Sign || !fns->C_VerifyInit || !fns->C_Verify)
        return QStringLiteral("тестовая подпись: функции подписи недоступны");

    CK_MECHANISM mech;
    mech.pParameter = nullptr;
    mech.ulParameterLen = 0;
    CK_ULONG dataLen = 0;
    if (keyType == CKK_GOSTR3410) {
        mech.mechanism = CKM_GOSTR3410;
        dataLen = 32;
    } else if (keyType == CKK_GOSTR3410_512) {
        mech.mechanism = CKM_GOSTR3410_512;
        dataLen = 64;
    } else if (keyType == CKK_RSA) {
        mech.mechanism = CKM_RSA_PKCS;
        dataLen = 20;
    } else {
        return QStringLiteral("тестовая подпись: неизвестный тип ключа");
    }

    // Фиксированный ненулевой буфер данных нужной длины.
    QByteArray data(static_cast<int>(dataLen), '\0');
    for (int i = 0; i < data.size(); ++i)
        data[i] = static_cast<char>(0x30 + (i % 10));
    CK_BYTE *dataPtr = reinterpret_cast<CK_BYTE *>(data.data());

    CK_RV rv = fns->C_SignInit(session, &mech, hPriv);
    if (rv != CKR_OK)
        return QStringLiteral("тестовая подпись: C_SignInit ") + rvHex(rv);

    // Двухпроходно: сначала длина подписи, затем сама подпись.
    CK_ULONG sigLen = 0;
    rv = fns->C_Sign(session, dataPtr, dataLen, nullptr, &sigLen);
    if (rv != CKR_OK)
        return QStringLiteral("тестовая подпись: C_Sign(длина) ") + rvHex(rv);
    QByteArray sig(static_cast<int>(sigLen), '\0');
    rv = fns->C_Sign(session, dataPtr, dataLen,
                     reinterpret_cast<CK_BYTE *>(sig.data()), &sigLen);
    if (rv != CKR_OK)
        return QStringLiteral("тестовая подпись: C_Sign ") + rvHex(rv);

    rv = fns->C_VerifyInit(session, &mech, hPub);
    if (rv != CKR_OK)
        return QStringLiteral("тестовая подпись: C_VerifyInit ") + rvHex(rv);
    rv = fns->C_Verify(session, dataPtr, dataLen,
                       reinterpret_cast<CK_BYTE *>(sig.data()), sigLen);
    if (rv == CKR_OK)
        return QStringLiteral("тестовая подпись: успех (подпись проверена)");
    return QStringLiteral("тестовая подпись: C_Verify ") + rvHex(rv);
}

} // namespace

namespace pkcs11 {

KeygenResult generateKeyPair(CK_FUNCTION_LIST_PREFIX *fns, unsigned long sessionHandle,
                             const QString &algorithm, const QString &label)
{
    KeygenResult res;
    if (!fns || !fns->C_GenerateKeyPair) {
        res.message = QStringLiteral("Библиотека не предоставляет C_GenerateKeyPair");
        return res;
    }
    const CK_SESSION_HANDLE session = static_cast<CK_SESSION_HANDLE>(sessionHandle);

    // Разбор запрошенного алгоритма/длины.
    const bool isGost256 = (algorithm == QStringLiteral("gost256"));
    const bool isGost512 = (algorithm == QStringLiteral("gost512"));
    const bool isRsa = algorithm.startsWith(QStringLiteral("rsa"));
    if (!isGost256 && !isGost512 && !isRsa) {
        res.message = QStringLiteral("Неизвестный алгоритм: ") + algorithm;
        return res;
    }

    // Значения-бэкенды для атрибутов должны жить до вызова C_GenerateKeyPair —
    // держим их в локальных переменных этой функции.
    CK_MECHANISM mech;
    mech.pParameter = nullptr;
    mech.ulParameterLen = 0;
    CK_KEY_TYPE keyType = 0;
    CK_ULONG modulusBits = 0;
    CK_BYTE publicExponent[] = { 0x01, 0x00, 0x01 };

    if (isGost256) {
        mech.mechanism = CKM_GOSTR3410_KEY_PAIR_GEN;
        keyType = CKK_GOSTR3410;
    } else if (isGost512) {
        mech.mechanism = CKM_GOSTR3410_512_KEY_PAIR_GEN;
        keyType = CKK_GOSTR3410_512;
    } else {
        mech.mechanism = CKM_RSA_PKCS_KEY_PAIR_GEN;
        keyType = CKK_RSA;
        modulusBits = (algorithm == QStringLiteral("rsa4096")) ? 4096 : 2048;
    }

    // Общий CKA_ID пары (16 случайных байт) — по нему на этапе D «приклеим»
    // сертификат к паре. Одна метка для обеих частей.
    const QByteArray id = QUuid::createUuid().toRfc4122();
    QByteArray labelBytes = label.toUtf8();

    CK_BBOOL yes = CK_TRUE_VALUE;
    CK_BBOOL no = 0;
    CK_OBJECT_CLASS pubClass = CKO_PUBLIC_KEY;
    CK_OBJECT_CLASS privClass = CKO_PRIVATE_KEY;

    QVector<CK_ATTRIBUTE> pub;
    QVector<CK_ATTRIBUTE> priv;

    // Общие атрибуты обеих частей пары. CKA_VERIFY/CKA_SIGN делают пару пригодной
    // для подписи — по ним же проходит тестовая подпись сразу после генерации.
    appendAttr(pub, CKA_CLASS, &pubClass, sizeof(pubClass));
    appendAttr(pub, CKA_KEY_TYPE, &keyType, sizeof(keyType));
    appendAttr(pub, CKA_TOKEN, &yes, sizeof(yes));
    appendAttr(pub, CKA_PRIVATE, &no, sizeof(no));
    appendAttr(pub, CKA_VERIFY, &yes, sizeof(yes));
    appendAttr(pub, CKA_ID, const_cast<char *>(id.constData()), static_cast<CK_ULONG>(id.size()));

    appendAttr(priv, CKA_CLASS, &privClass, sizeof(privClass));
    appendAttr(priv, CKA_KEY_TYPE, &keyType, sizeof(keyType));
    appendAttr(priv, CKA_TOKEN, &yes, sizeof(yes));
    appendAttr(priv, CKA_PRIVATE, &yes, sizeof(yes));
    appendAttr(priv, CKA_SIGN, &yes, sizeof(yes));
    appendAttr(priv, CKA_ID, const_cast<char *>(id.constData()), static_cast<CK_ULONG>(id.size()));

    if (!labelBytes.isEmpty()) {
        appendAttr(pub, CKA_LABEL, labelBytes.data(), static_cast<CK_ULONG>(labelBytes.size()));
        appendAttr(priv, CKA_LABEL, labelBytes.data(), static_cast<CK_ULONG>(labelBytes.size()));
    }

    if (isRsa) {
        appendAttr(pub, CKA_MODULUS_BITS, &modulusBits, sizeof(modulusBits));
        appendAttr(pub, CKA_PUBLIC_EXPONENT, publicExponent, sizeof(publicExponent));
    } else {
        const CK_BYTE *kp = isGost512 ? kGost512KeyParams : kGost256KeyParams;
        const CK_ULONG kpLen = isGost512 ? sizeof(kGost512KeyParams) : sizeof(kGost256KeyParams);
        const CK_BYTE *hp = isGost512 ? kGost512HashParams : kGost256HashParams;
        const CK_ULONG hpLen = isGost512 ? sizeof(kGost512HashParams) : sizeof(kGost256HashParams);
        // Параметры ГОСТ обязательны в обоих шаблонах (см. образцы Актив).
        appendAttr(pub, CKA_GOSTR3410_PARAMS, const_cast<CK_BYTE *>(kp), kpLen);
        appendAttr(pub, CKA_GOSTR3411_PARAMS, const_cast<CK_BYTE *>(hp), hpLen);
        appendAttr(priv, CKA_GOSTR3410_PARAMS, const_cast<CK_BYTE *>(kp), kpLen);
        appendAttr(priv, CKA_GOSTR3411_PARAMS, const_cast<CK_BYTE *>(hp), hpLen);
    }

    CK_OBJECT_HANDLE hPub = 0;
    CK_OBJECT_HANDLE hPriv = 0;
    const CK_RV rv = fns->C_GenerateKeyPair(session, &mech,
                                            pub.data(), static_cast<CK_ULONG>(pub.size()),
                                            priv.data(), static_cast<CK_ULONG>(priv.size()),
                                            &hPub, &hPriv);
    if (rv == CKR_OK) {
        res.ok = true;
        // Контроль работоспособности пары: подписываем и проверяем сразу, по
        // свежим дескрипторам. Результат — в сообщении (сама генерация успешна
        // независимо от исхода проверки).
        const QString sv = testSignVerify(fns, session, hPriv, hPub, keyType);
        res.message = QStringLiteral("Ключевая пара создана. ") + sv;
    } else {
        res.message = QStringLiteral("C_GenerateKeyPair: ") + rvHex(rv);
    }
    return res;
}

} // namespace pkcs11
