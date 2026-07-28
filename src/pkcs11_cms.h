#ifndef PKCS11_CMS_H
#define PKCS11_CMS_H

#include <QtCore/QByteArray>
#include <QtCore/QFunctionPointer>
#include <QtCore/QString>

struct CK_FUNCTION_LIST_PREFIX;

namespace pkcs11 {

struct CmsResult {
    bool ok = false;
    QString message;
    QString outputPath;
};

// Подписать файл в уже открытой залогиненной PKCS#11-сессии официальной
// расширенной функцией Рутокен C_EX_PKCS7Sign. Сертификат выбирается не только
// по CKA_ID, но и по точному DER, поэтому обновлённые сертификаты на одной
// ключевой паре не перепутаются. Закрытый ключ ищется по тому же CKA_ID.
//
// detached=true  → CMS без исходного содержимого, расширение .p7s
// detached=false → CMS с исходным содержимым, расширение .p7m
//
// Готовый CMS сохраняется через временный файл в том же каталоге и атомарное
// rename без перезаписи существующего пути.
CmsResult signFileCms(CK_FUNCTION_LIST_PREFIX *functions, unsigned long session,
                      QFunctionPointer exPkcs7Sign, QFunctionPointer exFreeBuffer,
                      const QByteArray &idBytes, const QByteArray &certificateDer,
                      const QString &sourcePath, bool detached,
                      const QString &outputDir, const QString &outputName);

} // namespace pkcs11

#endif // PKCS11_CMS_H
