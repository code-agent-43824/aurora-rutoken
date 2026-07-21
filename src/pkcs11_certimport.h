#ifndef PKCS11_CERTIMPORT_H
#define PKCS11_CERTIMPORT_H

#include <QtCore/QString>

struct CK_FUNCTION_LIST_PREFIX;

namespace pkcs11 {

struct ImportResult {
    bool ok = false;
    bool attached = false;   // приклеен к ключевой паре по открытому ключу
    QString message;
};

// Импорт X.509-сертификата из файла на токен (в уже открытой залогиненной
// R/W-сессии). Читает PEM или DER, разбирает тело, ищет на токене открытый ключ
// с тем же значением и при совпадении присваивает сертификату CKA_ID найденной
// пары (иначе CKA_ID = SHA-1 от открытого ключа). Пустой label → берётся CN из
// тела сертификата.
ImportResult importCertificateFromFile(CK_FUNCTION_LIST_PREFIX *functions, unsigned long session,
                                       const QString &filePath, const QString &label);

} // namespace pkcs11

#endif // PKCS11_CERTIMPORT_H
