#include "pkcs11_guard.h"

#include <QtCore/QMutex>

namespace pkcs11 {

QMutex &globalMutex()
{
    static QMutex mutex;
    return mutex;
}

} // namespace pkcs11
