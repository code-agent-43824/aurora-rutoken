#include "pkcs11_cms.h"

#include "pkcs11_errors.h"
#include "pkcs11_minimal.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QList>
#include <QtCore/QPair>
#include <QtCore/QTemporaryFile>

namespace {

// C_EX_PKCS7Sign принимает исходные данные одним буфером. Ограничение защищает
// 32-битные телефоны Авроры от неконтролируемого исчерпания памяти. Для
// detached и attached используется один и тот же официальный API.
const qint64 kMaximumInputSize = 64LL * 1024LL * 1024LL;

const CK_ULONG PKCS7_DETACHED_SIGNATURE = 0x01UL;
const CK_ULONG USE_HARDWARE_HASH = 0x02UL;

typedef CK_RV (*ExPkcs7SignFn)(CK_SESSION_HANDLE, CK_BYTE *, CK_ULONG,
                               CK_OBJECT_HANDLE, CK_BYTE **, CK_ULONG *,
                               CK_OBJECT_HANDLE, CK_OBJECT_HANDLE *, CK_ULONG,
                               CK_ULONG);
typedef CK_RV (*ExFreeBufferFn)(CK_BYTE *);

QByteArray readAttr(CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE session,
                    CK_OBJECT_HANDLE object, CK_ATTRIBUTE_TYPE type)
{
    CK_ATTRIBUTE attr;
    attr.type = type;
    attr.pValue = nullptr;
    attr.ulValueLen = 0;
    if (fns->C_GetAttributeValue(session, object, &attr, 1) != CKR_OK
            || attr.ulValueLen == 0
            || attr.ulValueLen == CK_UNAVAILABLE_INFORMATION) {
        return QByteArray();
    }
    QByteArray value(static_cast<int>(attr.ulValueLen), '\0');
    attr.pValue = value.data();
    if (fns->C_GetAttributeValue(session, object, &attr, 1) != CKR_OK)
        return QByteArray();
    value.truncate(static_cast<int>(attr.ulValueLen));
    return value;
}

QList<CK_OBJECT_HANDLE> findByClassAndId(CK_FUNCTION_LIST_PREFIX *fns,
                                         CK_SESSION_HANDLE session,
                                         CK_OBJECT_CLASS objectClass,
                                         const QByteArray &idBytes)
{
    QList<CK_OBJECT_HANDLE> result;
    CK_ATTRIBUTE attrs[2];
    attrs[0].type = CKA_CLASS;
    attrs[0].pValue = &objectClass;
    attrs[0].ulValueLen = sizeof(objectClass);
    attrs[1].type = CKA_ID;
    attrs[1].pValue = const_cast<char *>(idBytes.constData());
    attrs[1].ulValueLen = static_cast<CK_ULONG>(idBytes.size());

    CK_RV rv = fns->C_FindObjectsInit(session, attrs, 2);
    if (rv != CKR_OK)
        return result;

    for (;;) {
        CK_OBJECT_HANDLE handles[8];
        CK_ULONG found = 0;
        rv = fns->C_FindObjects(session, handles, 8, &found);
        if (rv != CKR_OK || found == 0)
            break;
        for (CK_ULONG i = 0; i < found; ++i)
            result.append(handles[i]);
    }
    fns->C_FindObjectsFinal(session);
    return result;
}

QString safeBaseName(const QString &requested, const QString &sourcePath, bool detached)
{
    QString base = requested.trimmed();
    if (base.isEmpty())
        base = QFileInfo(sourcePath).fileName();

    QString safe;
    for (int i = 0; i < base.size(); ++i) {
        const QChar c = base.at(i);
        if (c.isLetterOrNumber() || c == QLatin1Char('.') || c == QLatin1Char('_')
                || c == QLatin1Char('-') || c == QLatin1Char(' ')) {
            safe.append(c);
        }
    }
    safe = safe.trimmed();
    const QString expectedExt = detached ? QStringLiteral(".p7s") : QStringLiteral(".p7m");
    if (safe.endsWith(QStringLiteral(".p7s"), Qt::CaseInsensitive)
            || safe.endsWith(QStringLiteral(".p7m"), Qt::CaseInsensitive)) {
        safe.chop(4);
    }
    if (safe.isEmpty())
        safe = QStringLiteral("signature");
    return safe + expectedExt;
}

QPair<bool, QString> writeAtomically(const QString &path, const CK_BYTE *data, CK_ULONG size)
{
    if (QFileInfo::exists(path))
        return qMakePair(false, QStringLiteral("Файл уже существует: ") + path);

    const QFileInfo destination(path);
    QTemporaryFile temporary(
        QDir(destination.absolutePath()).filePath(QStringLiteral(".rutoken-cms-XXXXXX.tmp")));
    temporary.setAutoRemove(true);
    if (!temporary.open())
        return qMakePair(false, QStringLiteral("Не удалось создать временный файл в ")
                         + destination.absolutePath());

    const qint64 expected = static_cast<qint64>(size);
    if (temporary.write(reinterpret_cast<const char *>(data), expected) != expected
            || !temporary.flush()) {
        return qMakePair(false, QStringLiteral("Не удалось записать подпись во временный файл"));
    }
    temporary.close();

    const QString temporaryPath = temporary.fileName();
    temporary.setAutoRemove(false);
    if (!QFile::rename(temporaryPath, path)) {
        QFile::remove(temporaryPath);
        if (QFileInfo::exists(path))
            return qMakePair(false, QStringLiteral("Файл уже существует: ") + path);
        return qMakePair(false, QStringLiteral("Не удалось сохранить подпись: ") + path);
    }
    return qMakePair(true, QStringLiteral("Подпись сохранена: ") + path);
}

} // namespace

namespace pkcs11 {

CmsResult signFileCms(CK_FUNCTION_LIST_PREFIX *fns, unsigned long sessionHandle,
                      QFunctionPointer exPkcs7Sign, QFunctionPointer exFreeBuffer,
                      const QByteArray &idBytes, const QByteArray &certificateDer,
                      const QString &sourcePath, bool detached,
                      const QString &outputDir, const QString &outputName)
{
    CmsResult result;
    if (!fns || !fns->C_FindObjectsInit || !fns->C_FindObjects
            || !fns->C_FindObjectsFinal || !fns->C_GetAttributeValue) {
        result.message = QStringLiteral("Библиотека не предоставляет функции поиска объектов");
        return result;
    }
    const ExPkcs7SignFn sign = reinterpret_cast<ExPkcs7SignFn>(exPkcs7Sign);
    const ExFreeBufferFn freeBuffer = reinterpret_cast<ExFreeBufferFn>(exFreeBuffer);
    if (!sign || !freeBuffer) {
        result.message = QStringLiteral(
            "Библиотека Рутокен не предоставляет C_EX_PKCS7Sign/C_EX_FreeBuffer");
        return result;
    }
    if (idBytes.isEmpty() || certificateDer.isEmpty()) {
        result.message = QStringLiteral("У выбранного сертификата нет CKA_ID или DER");
        return result;
    }

    QFile input(sourcePath);
    const QFileInfo inputInfo(input);
    if (!inputInfo.exists() || !inputInfo.isFile()) {
        result.message = QStringLiteral("Исходный файл не найден: ") + sourcePath;
        return result;
    }
    if (inputInfo.size() > kMaximumInputSize) {
        result.message = QStringLiteral("Файл слишком большой для CMS API Рутокен (максимум 64 МБ)");
        return result;
    }
    if (!input.open(QIODevice::ReadOnly)) {
        result.message = QStringLiteral("Не удалось прочитать исходный файл: ") + sourcePath;
        return result;
    }
    QByteArray inputData = input.readAll();
    if (inputData.size() != inputInfo.size()) {
        result.message = QStringLiteral("Исходный файл прочитан не полностью");
        return result;
    }

    QString dir = outputDir.trimmed();
    if (dir.isEmpty())
        dir = inputInfo.absolutePath();
    if (!QDir().mkpath(dir)) {
        result.message = QStringLiteral("Не удалось создать каталог: ") + dir;
        return result;
    }
    const QString targetPath = QDir(dir).filePath(
        safeBaseName(outputName, sourcePath, detached));
    if (QFileInfo::exists(targetPath)) {
        result.message = QStringLiteral("Файл уже существует: ") + targetPath;
        return result;
    }

    const CK_SESSION_HANDLE session = static_cast<CK_SESSION_HANDLE>(sessionHandle);
    const QList<CK_OBJECT_HANDLE> certificates =
        findByClassAndId(fns, session, CKO_CERTIFICATE, idBytes);
    CK_OBJECT_HANDLE certificate = 0;
    for (CK_OBJECT_HANDLE handle : certificates) {
        if (readAttr(fns, session, handle, CKA_VALUE) == certificateDer) {
            certificate = handle;
            break;
        }
    }
    if (certificate == 0) {
        result.message = QStringLiteral(
            "Выбранный сертификат не найден на Рутокене (CKA_ID/DER не совпали)");
        return result;
    }

    const QList<CK_OBJECT_HANDLE> privateKeys =
        findByClassAndId(fns, session, CKO_PRIVATE_KEY, idBytes);
    if (privateKeys.isEmpty()) {
        result.message = QStringLiteral("Закрытый ключ выбранного сертификата не найден");
        return result;
    }
    if (privateKeys.size() > 1) {
        result.message = QStringLiteral(
            "Найдено несколько закрытых ключей с одним CKA_ID — подпись неоднозначна");
        return result;
    }

    CK_BYTE empty = 0;
    CK_BYTE *source = inputData.isEmpty()
        ? &empty : reinterpret_cast<CK_BYTE *>(inputData.data());
    CK_BYTE *envelope = nullptr;
    CK_ULONG envelopeSize = 0;
    const CK_ULONG flags = USE_HARDWARE_HASH
        | (detached ? PKCS7_DETACHED_SIGNATURE : 0UL);
    const CK_RV rv = sign(session, source, static_cast<CK_ULONG>(inputData.size()),
                          certificate, &envelope, &envelopeSize, privateKeys.first(),
                          nullptr, 0, flags);
    inputData.fill('\0');
    inputData.clear();
    if (rv != CKR_OK) {
        result.message = QStringLiteral("C_EX_PKCS7Sign: ") + pkcs11::rvMessage(rv);
        return result;
    }
    if (!envelope || envelopeSize == 0) {
        if (envelope)
            freeBuffer(envelope);
        result.message = QStringLiteral("C_EX_PKCS7Sign вернула пустой CMS");
        return result;
    }

    const QPair<bool, QString> saved =
        writeAtomically(targetPath, envelope, envelopeSize);
    const CK_RV freeRv = freeBuffer(envelope);
    if (!saved.first) {
        result.message = saved.second;
        return result;
    }
    if (freeRv != CKR_OK) {
        result.message = saved.second
            + QStringLiteral("; предупреждение C_EX_FreeBuffer: ")
            + pkcs11::rvMessage(freeRv);
        result.outputPath = targetPath;
        result.ok = true;
        return result;
    }

    result.ok = true;
    result.outputPath = targetPath;
    result.message = saved.second;
    return result;
}

} // namespace pkcs11
