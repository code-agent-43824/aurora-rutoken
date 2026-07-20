#ifndef PKCS11_GUARD_H
#define PKCS11_GUARD_H

class QMutex;

namespace pkcs11 {

// Общий мьютекс на весь процесс: C_Initialize/C_Finalize глобальны, поэтому
// фоновый опрос токенов (TokenWatcher) и операции сессии (TokenSession) не
// должны выполнять свои циклы init…finalize одновременно. Каждый берёт этот
// мьютекс на время своего изолированного цикла.
QMutex &globalMutex();

} // namespace pkcs11

#endif // PKCS11_GUARD_H
