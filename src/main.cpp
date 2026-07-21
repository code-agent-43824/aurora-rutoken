#include <auroraapp.h>
#include <QtQuick>

#include "diagnostics.h"
#include "tokensession.h"
#include "tokenwatcher.h"

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> application(Aurora::Application::application(argc, argv));
    application->setOrganizationName(QStringLiteral("ru.codeagent43824"));
    application->setApplicationName(QStringLiteral("rutokentestapp"));

    TokenWatcher tokenWatcher;
    TokenSession tokenSession;
    Diagnostics diagnostics;

    // Изменение набора токенов: сброс входа при пропаже USB-слота и снятие
    // подавления с отключённых USB-токенов.
    QObject::connect(&tokenWatcher, &TokenWatcher::tokensChanged, &tokenSession, [&]() {
        tokenSession.syncWithTokens(tokenWatcher.tokens());
    });

    QScopedPointer<QQuickView> view(Aurora::Application::createView());
    view->rootContext()->setContextProperty(QStringLiteral("tokenWatcher"), &tokenWatcher);
    view->rootContext()->setContextProperty(QStringLiteral("tokenSession"), &tokenSession);
    view->rootContext()->setContextProperty(QStringLiteral("diag"), &diagnostics);
    view->setSource(Aurora::Application::pathTo(QStringLiteral("qml/rutokentestapp.qml")));
    view->show();

    tokenWatcher.start();

    return application->exec();
}
