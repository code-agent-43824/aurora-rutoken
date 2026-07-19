#include <auroraapp.h>
#include <QtQuick>

#include "diagnostics.h"

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> application(Aurora::Application::application(argc, argv));
    application->setOrganizationName(QStringLiteral("ru.codeagent43824"));
    application->setApplicationName(QStringLiteral("rutokentestapp"));

    Diagnostics diagnostics;

    QScopedPointer<QQuickView> view(Aurora::Application::createView());
    view->rootContext()->setContextProperty(QStringLiteral("diag"), &diagnostics);
    view->setSource(Aurora::Application::pathTo(QStringLiteral("qml/rutokentestapp.qml")));
    view->show();

    return application->exec();
}
