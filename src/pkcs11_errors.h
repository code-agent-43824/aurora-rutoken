#ifndef PKCS11_ERRORS_H
#define PKCS11_ERRORS_H

#include <QtCore/QString>

namespace pkcs11 {

// Человекочитаемое сообщение для кода возврата PKCS#11 (CKR_*) на русском, с
// hex-кодом в скобках для диагностики. Например: «неверный механизм
// (0x00000070)». Неизвестный код — «код 0x…». Принимает unsigned long, чтобы не
// тянуть ABI-заголовок в вызывающие места (CK_RV = CK_ULONG = unsigned long).
QString rvMessage(unsigned long rv);

} // namespace pkcs11

#endif // PKCS11_ERRORS_H
