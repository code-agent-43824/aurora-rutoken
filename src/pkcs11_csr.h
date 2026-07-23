#ifndef PKCS11_CSR_H
#define PKCS11_CSR_H

#include <QtCore/QString>

struct CK_FUNCTION_LIST_PREFIX;

namespace pkcs11 {

// Поля Subject (DN) запроса. Пустые пропускаются. CN обязателен (проверяет UI).
struct CsrDn {
    QString commonName;         // CN
    QString organization;       // O
    QString organizationUnit;   // OU
    QString country;            // C  (PrintableString, обычно 2 буквы)
    QString locality;           // L
    QString state;              // ST
    QString email;              // emailAddress (IA5String)
};

struct CsrResult {
    bool ok = false;
    QString pem;      // PEM запроса (-----BEGIN CERTIFICATE REQUEST-----) при успехе
    QString message;  // человекочитаемое сообщение
};

// Сформировать запрос на сертификат PKCS#10 для ключевой пары на токене
// (найденной по CKA_ID) в уже открытой залогиненной сессии. Открытый ключ и его
// параметры читаются с токена, CertificationRequestInfo подписывается закрытым
// ключом на токене (механизм «подпись с хешем» по типу ключа: ГОСТ 256/512 или
// RSA). Возвращает PEM. Порядок байтов ключа/подписи ГОСТ — по RFC 4491/9215,
// сверяется на устройстве.
CsrResult createCsr(CK_FUNCTION_LIST_PREFIX *functions, unsigned long session,
                    const QByteArray &idBytes, const CsrDn &dn);

} // namespace pkcs11

#endif // PKCS11_CSR_H
