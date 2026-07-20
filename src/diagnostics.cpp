#include "diagnostics.h"
#include "pkcs11_minimal.h"

#include <QtConcurrent/QtConcurrent>
#include <QtCore/QLibrary>
#include <QtCore/QVector>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusConnectionInterface>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusObjectPath>
#include <QtDBus/QDBusReply>
#include <QtDBus/QDBusArgument>

#include <cstring>

// Минимальные типы/константы pcsc-lite (winscard.h не тянем, т.к. библиотека
// грузится через dlopen/QLibrary). В pcsc-lite LONG=long, DWORD=unsigned long —
// размеры корректны и на armv7hl (32 бита), и на aarch64 (64 бита).
typedef long PcscLong;
typedef unsigned long PcscDword;
typedef PcscLong PcscContext;

static const PcscDword kScardScopeSystem = 2;
static const PcscDword kScardAutoAllocate = static_cast<PcscDword>(-1);

typedef PcscLong (*FnEstablishContext)(PcscDword, const void *, const void *, PcscContext *);
typedef PcscLong (*FnReleaseContext)(PcscContext);
typedef PcscLong (*FnListReaders)(PcscContext, const char *, char *, PcscDword *);
typedef PcscLong (*FnFreeMemory)(PcscContext, const void *);
typedef const char *(*FnStringifyError)(PcscLong);

namespace {

QString scardErrorName(PcscLong rv)
{
    switch (static_cast<quint32>(rv)) {
    case 0x00000000: return QStringLiteral("SCARD_S_SUCCESS");
    case 0x80100001: return QStringLiteral("SCARD_F_INTERNAL_ERROR");
    case 0x80100006: return QStringLiteral("SCARD_E_NO_MEMORY");
    case 0x80100017: return QStringLiteral("SCARD_E_READER_UNAVAILABLE");
    case 0x8010001D: return QStringLiteral("SCARD_E_NO_SERVICE");
    case 0x8010001E: return QStringLiteral("SCARD_E_SERVICE_STOPPED");
    case 0x8010002E: return QStringLiteral("SCARD_E_NO_READERS_AVAILABLE");
    case 0x80100069: return QStringLiteral("SCARD_W_REMOVED_CARD");
    default: return QString();
    }
}

QString scardErrorText(PcscLong rv, FnStringifyError stringify)
{
    QString text = QStringLiteral("0x%1").arg(static_cast<quint32>(rv), 8, 16, QLatin1Char('0'));
    QString name = scardErrorName(rv);
    if (name.isEmpty() && stringify)
        name = QString::fromLatin1(stringify(rv));
    if (!name.isEmpty())
        text += QStringLiteral(" (") + name + QLatin1Char(')');
    return text;
}

QString pkcs11Rv(CK_RV rv)
{
    return QStringLiteral("0x%1").arg(static_cast<qulonglong>(rv),
                                      sizeof(CK_RV) * 2, 16, QLatin1Char('0'));
}

QString fixedPkcs11Text(const CK_UTF8CHAR *value, int size)
{
    QByteArray bytes(reinterpret_cast<const char *>(value), size);
    while (!bytes.isEmpty() && (bytes.endsWith(' ') || bytes.endsWith('\0')))
        bytes.chop(1);
    return QString::fromUtf8(bytes).trimmed();
}

QVariantMap makeRow(const QString &id, int ok, const QString &detail,
                    const QString &title = QString())
{
    QVariantMap row;
    row.insert(QStringLiteral("id"), id);
    row.insert(QStringLiteral("ok"), ok); // 1 — успех, 0 — провал, -1 — предупреждение/нейтрально
    row.insert(QStringLiteral("detail"), detail);
    row.insert(QStringLiteral("title"), title); // если не пусто — заголовок берётся отсюда
    return row;
}

// Эвристика типа подключения по имени PC/SC-слота (ридера). USB-Рутокен на
// Авроре виден как «Aktiv Rutoken ECP …» (подтверждено на устройстве в v0.0.2);
// NFC-считыватель — по «nfc» в имени. Сырое имя всё равно показывается в
// деталях, чтобы уточнить эвристику на реальном железе владельца.
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

// Перечисление подключённых токенов через уже инициализированный модуль.
QVariantList enumerateTokens(CK_FUNCTION_LIST_PREFIX *fns)
{
    QVariantList rows;
    if (!fns->C_GetSlotList || !fns->C_GetSlotInfo || !fns->C_GetTokenInfo) {
        rows.append(makeRow(QStringLiteral("tokens"), -1,
                            QStringLiteral("перечисление токенов недоступно в этой версии библиотеки")));
        return rows;
    }

    CK_ULONG count = 0;
    CK_RV rv = fns->C_GetSlotList(CK_TRUE_VALUE, nullptr, &count); // только слоты с токеном
    if (rv != CKR_OK) {
        rows.append(makeRow(QStringLiteral("tokens"), 0,
                            QStringLiteral("C_GetSlotList: ") + pkcs11Rv(rv)));
        return rows;
    }
    if (count == 0) {
        rows.append(makeRow(QStringLiteral("tokens"), -1,
                            QStringLiteral("токен не подключён (подключите Рутокен по USB или поднесите к NFC)")));
        return rows;
    }

    QVector<CK_SLOT_ID> slots(static_cast<int>(count));
    rv = fns->C_GetSlotList(CK_TRUE_VALUE, slots.data(), &count);
    if (rv != CKR_OK) {
        rows.append(makeRow(QStringLiteral("tokens"), 0,
                            QStringLiteral("C_GetSlotList (2): ") + pkcs11Rv(rv)));
        return rows;
    }

    rows.append(makeRow(QStringLiteral("tokens"), 1,
                        QStringLiteral("подключено токенов: %1").arg(count)));

    for (CK_ULONG i = 0; i < count; ++i) {
        CK_SLOT_INFO slotInfo;
        std::memset(&slotInfo, 0, sizeof(slotInfo));
        QString slotName;
        QString connType;
        if (fns->C_GetSlotInfo(slots[static_cast<int>(i)], &slotInfo) == CKR_OK) {
            slotName = fixedPkcs11Text(slotInfo.slotDescription, sizeof(slotInfo.slotDescription));
            connType = connectionType(slotName);
        }

        CK_TOKEN_INFO tokenInfo;
        std::memset(&tokenInfo, 0, sizeof(tokenInfo));
        rv = fns->C_GetTokenInfo(slots[static_cast<int>(i)], &tokenInfo);

        const QString connLabel = connType.isEmpty() ? QStringLiteral("тип ?") : connType;
        if (rv != CKR_OK) {
            rows.append(makeRow(QStringLiteral("token"), 0,
                                QStringLiteral("C_GetTokenInfo: ") + pkcs11Rv(rv)
                                    + QStringLiteral("; слот/ридер: ") + slotName,
                                QStringLiteral("Слот %1 — %2")
                                    .arg(static_cast<qulonglong>(slots[static_cast<int>(i)]))
                                    .arg(connLabel)));
            continue;
        }

        const QString label = fixedPkcs11Text(tokenInfo.label, sizeof(tokenInfo.label));
        const QString serial = fixedPkcs11Text(tokenInfo.serialNumber, sizeof(tokenInfo.serialNumber));
        const QString model = fixedPkcs11Text(tokenInfo.model, sizeof(tokenInfo.model));
        const QString manuf = fixedPkcs11Text(tokenInfo.manufacturerID, sizeof(tokenInfo.manufacturerID));

        const QString title = QStringLiteral("%1 — %2")
            .arg(label.isEmpty() ? QStringLiteral("Рутокен без метки") : label, connLabel);

        QStringList det;
        det << QStringLiteral("серийный №: ") + (serial.isEmpty() ? QStringLiteral("—") : serial);
        if (!model.isEmpty())
            det << QStringLiteral("модель: ") + model;
        if (!manuf.isEmpty())
            det << QStringLiteral("производитель: ") + manuf;
        det << QStringLiteral("прошивка %1.%2; железо %3.%4")
                   .arg(static_cast<int>(tokenInfo.firmwareVersion.major))
                   .arg(static_cast<int>(tokenInfo.firmwareVersion.minor))
                   .arg(static_cast<int>(tokenInfo.hardwareVersion.major))
                   .arg(static_cast<int>(tokenInfo.hardwareVersion.minor));

        QStringList flags;
        if (tokenInfo.flags & CKF_TOKEN_INITIALIZED)
            flags << QStringLiteral("инициализирован");
        if (tokenInfo.flags & CKF_LOGIN_REQUIRED)
            flags << QStringLiteral("нужен вход (PIN)");
        if (tokenInfo.flags & CKF_USER_PIN_INITIALIZED)
            flags << QStringLiteral("PIN пользователя задан");
        if (tokenInfo.flags & CKF_WRITE_PROTECTED)
            flags << QStringLiteral("защита записи");
        if (!flags.isEmpty())
            det << flags.join(QStringLiteral(", "));

        det << QStringLiteral("слот/ридер: ") + (slotName.isEmpty() ? QStringLiteral("—") : slotName);

        rows.append(makeRow(QStringLiteral("token"), 1, det.join(QStringLiteral("\n")), title));
    }

    return rows;
}

} // namespace

Diagnostics::Diagnostics(QObject *parent)
    : QObject(parent)
{
    // Результаты PC/SC и PKCS#11 приходят из рабочего потока; соединение auto-queued.
    connect(this, &Diagnostics::backendRowsReady, this, [this](const QVariantList &backendRows) {
        m_rows = m_nfcRows + backendRows;
        m_running = false;
        emit rowsChanged();
        emit runningChanged();
    });
}

void Diagnostics::refresh()
{
    if (m_running)
        return;
    m_running = true;
    emit runningChanged();

    m_nfcRows = probeNfc(); // быстрые D-Bus-проверки — в главном потоке
    QtConcurrent::run(this, &Diagnostics::probeBackends);
}

QVariantList Diagnostics::probeNfc() const
{
    QVariantList rows;
    const QString service = QStringLiteral("org.sailfishos.nfc.daemon");

    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        rows.append(makeRow(QStringLiteral("nfcsvc"), 0,
                            QStringLiteral("D-Bus system bus: ") + bus.lastError().message()));
        return rows;
    }

    QDBusReply<bool> registered = bus.interface()->isServiceRegistered(service);
    if (!registered.isValid() || !registered.value()) {
        rows.append(makeRow(QStringLiteral("nfcsvc"), 0, service + QStringLiteral(" не зарегистрирован")));
        return rows;
    }
    rows.append(makeRow(QStringLiteral("nfcsvc"), 1, service));

    // Версия демона и адаптеры — интерфейс org.sailfishos.nfc.Daemon на "/"
    // (имена — из демо NfcUseCases OMP).
    QDBusInterface daemon(service, QStringLiteral("/"), QStringLiteral("org.sailfishos.nfc.Daemon"), bus);
    daemon.setTimeout(2000);

    QStringList details;
    QDBusReply<int> version = daemon.call(QStringLiteral("GetDaemonVersion"));
    if (version.isValid())
        details << QStringLiteral("nfcd v%1").arg(version.value());

    int adapterCount = -1;
    QStringList adapterPaths;
    QDBusMessage reply = daemon.call(QStringLiteral("GetAdapters"));
    if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
        const QDBusArgument arg = reply.arguments().first().value<QDBusArgument>();
        arg.beginArray();
        while (!arg.atEnd()) {
            QDBusObjectPath path;
            arg >> path;
            adapterPaths << path.path();
        }
        arg.endArray();
        adapterCount = adapterPaths.size();
        details << QStringLiteral("адаптеров: %1%2").arg(adapterCount)
                       .arg(adapterPaths.isEmpty()
                            ? QString()
                            : QStringLiteral(" (") + adapterPaths.join(QStringLiteral(", ")) + QLatin1Char(')'));
    } else {
        details << QStringLiteral("GetAdapters: ") + reply.errorMessage();
    }

    rows.append(makeRow(QStringLiteral("nfcinfo"),
                        adapterCount > 0 ? 1 : (adapterCount == 0 ? -1 : 0),
                        details.join(QStringLiteral("; "))));
    return rows;
}

void Diagnostics::probeBackends()
{
    emit backendRowsReady(probePcsc() + probePkcs11());
}

QVariantList Diagnostics::probePcsc() const
{
    QVariantList rows;

    QLibrary lib(QStringLiteral("libpcsclite"), 1);
    if (!lib.load()) {
        rows.append(makeRow(QStringLiteral("pcsclib"), 0, lib.errorString()));
        return rows;
    }

    FnEstablishContext establish = reinterpret_cast<FnEstablishContext>(lib.resolve("SCardEstablishContext"));
    FnReleaseContext release = reinterpret_cast<FnReleaseContext>(lib.resolve("SCardReleaseContext"));
    FnListReaders listReaders = reinterpret_cast<FnListReaders>(lib.resolve("SCardListReaders"));
    FnFreeMemory freeMemory = reinterpret_cast<FnFreeMemory>(lib.resolve("SCardFreeMemory"));
    FnStringifyError stringify = reinterpret_cast<FnStringifyError>(lib.resolve("pcsc_stringify_error"));

    if (!establish || !release || !listReaders) {
        rows.append(makeRow(QStringLiteral("pcsclib"), 0,
                            QStringLiteral("библиотека загружена, но SCard*-символы не найдены")));
        return rows;
    }
    rows.append(makeRow(QStringLiteral("pcsclib"), 1, lib.fileName()));

    PcscContext context = 0;
    PcscLong rv = establish(kScardScopeSystem, nullptr, nullptr, &context);
    if (rv != 0) {
        // SCARD_E_NO_SERVICE / SERVICE_STOPPED здесь означают «pcscd не запущен».
        rows.append(makeRow(QStringLiteral("context"), 0, scardErrorText(rv, stringify)));
        return rows;
    }
    rows.append(makeRow(QStringLiteral("context"), 1,
                        QStringLiteral("SCardEstablishContext: OK (pcscd отвечает)")));

    char *readersBuf = nullptr;
    PcscDword readersLen = kScardAutoAllocate;
    rv = listReaders(context, nullptr, reinterpret_cast<char *>(&readersBuf), &readersLen);
    if (rv == 0 && readersBuf) {
        QStringList readers;
        for (const char *p = readersBuf; *p; p += strlen(p) + 1)
            readers << QString::fromUtf8(p);
        if (freeMemory)
            freeMemory(context, readersBuf);
        rows.append(makeRow(QStringLiteral("readers"), readers.isEmpty() ? -1 : 1,
                            readers.isEmpty() ? QStringLiteral("список пуст")
                                              : readers.join(QStringLiteral("; "))));
    } else if (static_cast<quint32>(rv) == 0x8010002E) { // SCARD_E_NO_READERS_AVAILABLE
        rows.append(makeRow(QStringLiteral("readers"), -1,
                            QStringLiteral("ридеров сейчас нет — подключите токен (")
                                + scardErrorText(rv, stringify) + QLatin1Char(')')));
    } else {
        rows.append(makeRow(QStringLiteral("readers"), 0, scardErrorText(rv, stringify)));
    }

    release(context);
    return rows;
}

QVariantList Diagnostics::probePkcs11() const
{
    QVariantList rows;
    const QString path = QStringLiteral(
        "/usr/lib/3rdparty/ru.rutoken.librtpkcs11ecp/librtpkcs11ecp.so");

    QLibrary library(path);
    if (!library.load()) {
        rows.append(makeRow(QStringLiteral("pkcs11lib"), 0,
                            path + QStringLiteral(": ") + library.errorString()));
        return rows;
    }
    rows.append(makeRow(QStringLiteral("pkcs11lib"), 1, path));

    CK_C_GetFunctionList getFunctionList =
        reinterpret_cast<CK_C_GetFunctionList>(library.resolve("C_GetFunctionList"));
    if (!getFunctionList) {
        rows.append(makeRow(QStringLiteral("pkcs11init"), 0,
                            QStringLiteral("C_GetFunctionList не найден")));
        return rows;
    }

    CK_FUNCTION_LIST_PREFIX *functions = nullptr;
    CK_RV rv = getFunctionList(&functions);
    if (rv != CKR_OK || !functions || !functions->C_Initialize
            || !functions->C_Finalize || !functions->C_GetInfo) {
        rows.append(makeRow(QStringLiteral("pkcs11init"), 0,
                            QStringLiteral("C_GetFunctionList: ") + pkcs11Rv(rv)));
        return rows;
    }

    rv = functions->C_Initialize(nullptr);
    const bool ownsInitialization = rv == CKR_OK;
    if (!ownsInitialization && rv != CKR_CRYPTOKI_ALREADY_INITIALIZED) {
        rows.append(makeRow(QStringLiteral("pkcs11init"), 0,
                            QStringLiteral("C_Initialize: ") + pkcs11Rv(rv)));
        return rows;
    }
    rows.append(makeRow(QStringLiteral("pkcs11init"), 1,
                        QStringLiteral("C_Initialize: OK; interface %1.%2")
                            .arg(static_cast<int>(functions->version.major))
                            .arg(static_cast<int>(functions->version.minor))));

    CK_INFO info;
    std::memset(&info, 0, sizeof(info));
    rv = functions->C_GetInfo(&info);
    if (rv == CKR_OK) {
        const QString detail = QStringLiteral("Cryptoki %1.%2; library %3.%4; %5; %6")
            .arg(static_cast<int>(info.cryptokiVersion.major))
            .arg(static_cast<int>(info.cryptokiVersion.minor))
            .arg(static_cast<int>(info.libraryVersion.major))
            .arg(static_cast<int>(info.libraryVersion.minor))
            .arg(fixedPkcs11Text(info.manufacturerID, sizeof(info.manufacturerID)))
            .arg(fixedPkcs11Text(info.libraryDescription, sizeof(info.libraryDescription)));
        rows.append(makeRow(QStringLiteral("pkcs11info"), 1, detail));
    } else {
        rows.append(makeRow(QStringLiteral("pkcs11info"), 0,
                            QStringLiteral("C_GetInfo: ") + pkcs11Rv(rv)));
    }

    // v0.0.4: информация о подключённых токенах (USB и NFC).
    rows += enumerateTokens(functions);

    if (ownsInitialization) {
        const CK_RV finalizeRv = functions->C_Finalize(nullptr);
        if (finalizeRv != CKR_OK) {
            rows.append(makeRow(QStringLiteral("pkcs11finalize"), 0,
                                QStringLiteral("C_Finalize: ") + pkcs11Rv(finalizeRv)));
        } else {
            rows.append(makeRow(QStringLiteral("pkcs11finalize"), 1,
                                QStringLiteral("C_Finalize: OK")));
        }
    } else {
        rows.append(makeRow(QStringLiteral("pkcs11finalize"), -1,
                            QStringLiteral("модуль уже был инициализирован; не финализируем чужую сессию")));
    }

    return rows;
}
