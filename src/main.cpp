#include <auroraapp.h>
#include <QtCore/QCoreApplication>
#include <QtQuick>

#include "appsettings.h"
#include "cryptoprosession.h"
#include "diagnostics.h"
#include "tokensession.h"
#include "tokenwatcher.h"

// Версия приложения (для показа в диагностике). Держать синхронной с
// rpm/*.spec (Version-Release).
static const char *const kAppVersion = "1.3.0-12";

int main(int argc, char *argv[])
{
    // Второй аргумент режима чтения — набор ГОСТ-провайдеров из настроек
    // (список номеров через запятую). Секрета в нём нет; PIN-код по-прежнему
    // передаётся только через stdin режима записи.
    if ((argc == 2 || argc == 3)
            && QByteArray(argv[1]) == QByteArrayLiteral("--cryptopro-scan-helper")) {
        QCoreApplication helperApplication(argc, argv);
        return CryptoProSession::runScanHelper();
    }
    if (argc == 2
            && QByteArray(argv[1]) == QByteArrayLiteral("--cryptopro-write-helper")) {
        QCoreApplication helperApplication(argc, argv);
        return CryptoProSession::runWriteHelper();
    }
    if (argc == 2
            && QByteArray(argv[1]) == QByteArrayLiteral("--pkcs11-slot-event-helper")) {
        QCoreApplication helperApplication(argc, argv);
        return TokenWatcher::runSlotEventHelper();
    }

    QScopedPointer<QGuiApplication> application(Aurora::Application::application(argc, argv));
    application->setOrganizationName(QStringLiteral("ru.codeagent43824"));
    application->setApplicationName(QStringLiteral("rutokentestapp"));

    AppSettings appSettings;
    TokenWatcher tokenWatcher;
    TokenSession tokenSession;
    CryptoProSession cryptoProSession;
    Diagnostics diagnostics;

    const auto applyCryptoProSetting = [&]() {
        const bool enabled = appSettings.cryptoProEnabled();
        diagnostics.setCryptoProEnabled(enabled);
        cryptoProSession.setProviderTypes(appSettings.cryptoProProviderTypeList());
        cryptoProSession.setEnabled(enabled);
        cryptoProSession.syncWithTokens(tokenWatcher.tokens());
    };
    QObject::connect(&appSettings, &AppSettings::cryptoProEnabledChanged,
                     &cryptoProSession, applyCryptoProSetting);
    // Смена набора провайдеров меняет и то, что будет прочитано, и то, где
    // разрешено создавать контейнер, поэтому применяется тем же путём.
    QObject::connect(&appSettings, &AppSettings::cryptoProProviderTypesChanged,
                     &cryptoProSession, applyCryptoProSetting);
    QObject::connect(&cryptoProSession, &CryptoProSession::changed,
                     &diagnostics, [&]() {
        diagnostics.setCryptoProLibraries(cryptoProSession.loadedLibraries());
        diagnostics.setCryptoProVersion(cryptoProSession.cspVersion());
    });
    applyCryptoProSetting();

    // Изменение набора токенов: сброс входа при пропаже USB-слота и снятие
    // подавления с отключённых USB-токенов.
    QObject::connect(&tokenWatcher, &TokenWatcher::tokensChanged, &tokenSession, [&]() {
        tokenSession.syncWithTokens(tokenWatcher.tokens());
        cryptoProSession.syncWithTokens(tokenWatcher.tokens());
    });

    QScopedPointer<QQuickView> view(Aurora::Application::createView());
    view->rootContext()->setContextProperty(QStringLiteral("tokenWatcher"), &tokenWatcher);
    view->rootContext()->setContextProperty(QStringLiteral("tokenSession"), &tokenSession);
    view->rootContext()->setContextProperty(QStringLiteral("cryptoProSession"), &cryptoProSession);
    view->rootContext()->setContextProperty(QStringLiteral("diag"), &diagnostics);
    view->rootContext()->setContextProperty(QStringLiteral("appSettings"), &appSettings);
    view->rootContext()->setContextProperty(QStringLiteral("appVersion"), QString::fromLatin1(kAppVersion));
    view->setSource(Aurora::Application::pathTo(QStringLiteral("qml/rutokentestapp.qml")));
    view->show();

    tokenWatcher.start();

    return application->exec();
}
