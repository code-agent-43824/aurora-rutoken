#include "pkcs11_tokens.h"
#include "pkcs11_minimal.h"

#include <QtCore/QStringList>
#include <QtCore/QVariantMap>
#include <QtCore/QVector>

#include <cstring>

namespace {

QString fixedText(const CK_UTF8CHAR *value, int size)
{
    QByteArray bytes(reinterpret_cast<const char *>(value), size);
    while (!bytes.isEmpty() && (bytes.endsWith(' ') || bytes.endsWith('\0')))
        bytes.chop(1);
    return QString::fromUtf8(bytes).trimmed();
}

QString versionText(const CK_VERSION &v)
{
    return QStringLiteral("%1.%2")
        .arg(static_cast<int>(v.major))
        .arg(static_cast<int>(v.minor));
}

} // namespace

namespace pkcs11 {

QString connectionType(const QString &slotName)
{
    const QString low = slotName.toLower();
    if (low.contains(QStringLiteral("nfc")) || low.contains(QStringLiteral("contactless")))
        return QStringLiteral("NFC");
    if (low.contains(QStringLiteral("rutoken")) || low.contains(QStringLiteral("aktiv"))
            || low.contains(QStringLiteral("ccid")) || low.contains(QStringLiteral("usb")))
        return QStringLiteral("USB");
    return QString();
}

QVariantList listConnectedTokens(CK_FUNCTION_LIST_PREFIX *functions)
{
    QVariantList out;
    if (!functions || !functions->C_GetSlotList || !functions->C_GetSlotInfo
            || !functions->C_GetTokenInfo)
        return out;

    CK_ULONG count = 0;
    if (functions->C_GetSlotList(CK_TRUE_VALUE, nullptr, &count) != CKR_OK || count == 0)
        return out;

    QVector<CK_SLOT_ID> slotIds(static_cast<int>(count));
    if (functions->C_GetSlotList(CK_TRUE_VALUE, slotIds.data(), &count) != CKR_OK)
        return out;

    for (CK_ULONG i = 0; i < count; ++i) {
        const CK_SLOT_ID id = slotIds[static_cast<int>(i)];

        CK_SLOT_INFO slotInfo;
        std::memset(&slotInfo, 0, sizeof(slotInfo));
        QString slotName;
        QString connection;
        if (functions->C_GetSlotInfo(id, &slotInfo) == CKR_OK) {
            slotName = fixedText(slotInfo.slotDescription, sizeof(slotInfo.slotDescription));
            connection = connectionType(slotName);
        }

        CK_TOKEN_INFO tokenInfo;
        std::memset(&tokenInfo, 0, sizeof(tokenInfo));
        if (functions->C_GetTokenInfo(id, &tokenInfo) != CKR_OK)
            continue;

        QStringList flags;
        if (tokenInfo.flags & CKF_TOKEN_INITIALIZED)
            flags << QStringLiteral("инициализирован");
        if (tokenInfo.flags & CKF_LOGIN_REQUIRED)
            flags << QStringLiteral("нужен вход (PIN)");
        if (tokenInfo.flags & CKF_USER_PIN_INITIALIZED)
            flags << QStringLiteral("PIN пользователя задан");
        if (tokenInfo.flags & CKF_WRITE_PROTECTED)
            flags << QStringLiteral("защита записи");

        QVariantMap card;
        card.insert(QStringLiteral("label"), fixedText(tokenInfo.label, sizeof(tokenInfo.label)));
        card.insert(QStringLiteral("serial"), fixedText(tokenInfo.serialNumber, sizeof(tokenInfo.serialNumber)));
        card.insert(QStringLiteral("model"), fixedText(tokenInfo.model, sizeof(tokenInfo.model)));
        card.insert(QStringLiteral("manufacturer"), fixedText(tokenInfo.manufacturerID, sizeof(tokenInfo.manufacturerID)));
        card.insert(QStringLiteral("connection"), connection);
        card.insert(QStringLiteral("slotName"), slotName);
        card.insert(QStringLiteral("slotId"), QVariant::fromValue<qulonglong>(id));
        card.insert(QStringLiteral("firmware"), versionText(tokenInfo.firmwareVersion));
        card.insert(QStringLiteral("hardware"), versionText(tokenInfo.hardwareVersion));
        card.insert(QStringLiteral("flags"), flags.join(QStringLiteral(", ")));
        card.insert(QStringLiteral("present"), true);
        out.append(card);
    }

    return out;
}

} // namespace pkcs11
