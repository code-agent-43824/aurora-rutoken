#include "diagnostics.h"

#include <QtConcurrent/QtConcurrent>
#include <QtCore/QLibrary>
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

QVariantMap makeRow(const QString &id, int ok, const QString &detail)
{
    QVariantMap row;
    row.insert(QStringLiteral("id"), id);
    row.insert(QStringLiteral("ok"), ok); // 1 — успех, 0 — провал, -1 — предупреждение/нейтрально
    row.insert(QStringLiteral("detail"), detail);
    return row;
}

} // namespace

Diagnostics::Diagnostics(QObject *parent)
    : QObject(parent)
{
    // Результаты PC/SC приходят из рабочего потока; соединение авто-queued.
    connect(this, &Diagnostics::pcscRowsReady, this, [this](const QVariantList &pcscRows) {
        m_rows = m_nfcRows + pcscRows;
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
    QtConcurrent::run(this, &Diagnostics::probePcsc);
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

void Diagnostics::probePcsc()
{
    QVariantList rows;

    QLibrary lib(QStringLiteral("libpcsclite"), 1);
    if (!lib.load()) {
        rows.append(makeRow(QStringLiteral("pcsclib"), 0, lib.errorString()));
        emit pcscRowsReady(rows);
        return;
    }

    FnEstablishContext establish = reinterpret_cast<FnEstablishContext>(lib.resolve("SCardEstablishContext"));
    FnReleaseContext release = reinterpret_cast<FnReleaseContext>(lib.resolve("SCardReleaseContext"));
    FnListReaders listReaders = reinterpret_cast<FnListReaders>(lib.resolve("SCardListReaders"));
    FnFreeMemory freeMemory = reinterpret_cast<FnFreeMemory>(lib.resolve("SCardFreeMemory"));
    FnStringifyError stringify = reinterpret_cast<FnStringifyError>(lib.resolve("pcsc_stringify_error"));

    if (!establish || !release || !listReaders) {
        rows.append(makeRow(QStringLiteral("pcsclib"), 0,
                            QStringLiteral("библиотека загружена, но SCard*-символы не найдены")));
        emit pcscRowsReady(rows);
        return;
    }
    rows.append(makeRow(QStringLiteral("pcsclib"), 1, lib.fileName()));

    PcscContext context = 0;
    PcscLong rv = establish(kScardScopeSystem, nullptr, nullptr, &context);
    if (rv != 0) {
        // SCARD_E_NO_SERVICE / SERVICE_STOPPED здесь означают «pcscd не запущен».
        rows.append(makeRow(QStringLiteral("context"), 0, scardErrorText(rv, stringify)));
        emit pcscRowsReady(rows);
        return;
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
    emit pcscRowsReady(rows);
}
