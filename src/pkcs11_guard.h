#ifndef PKCS11_GUARD_H
#define PKCS11_GUARD_H

class QMutex;

namespace pkcs11 {

// Общий мьютекс на весь процесс: C_Initialize/C_Finalize глобальны, поэтому
// event-driven снимок устройств (TokenWatcher), операции сессии
// (TokenSession) и проход диагностики (Diagnostics) не должны выполнять свои
// циклы init…finalize одновременно. Каждый берёт этот мьютекс на время своего
// изолированного цикла; ci/check-source-invariants.sh это проверяет.
QMutex &globalMutex();

} // namespace pkcs11

#endif // PKCS11_GUARD_H
