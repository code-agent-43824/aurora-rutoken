#ifndef PKCS11_KEYGEN_H
#define PKCS11_KEYGEN_H

#include <QtCore/QString>

struct CK_FUNCTION_LIST_PREFIX;

namespace pkcs11 {

struct KeygenResult {
    bool ok = false;
    QString message;
};

// Генерация ключевой пары на токене в уже открытой залогиненной R/W-сессии.
// algorithm: "gost256" | "gost512" | "rsa2048" | "rsa4096".
// Обе части пары получают одинаковый CKA_ID (16 случайных байт) и одну метку —
// по CKA_ID на этапе D к паре «приклеивается» импортируемый сертификат.
// Параметры ГОСТ/RSA берутся из docs/RESEARCH.md §5в.
KeygenResult generateKeyPair(CK_FUNCTION_LIST_PREFIX *functions, unsigned long session,
                             const QString &algorithm, const QString &label);

} // namespace pkcs11

#endif // PKCS11_KEYGEN_H
