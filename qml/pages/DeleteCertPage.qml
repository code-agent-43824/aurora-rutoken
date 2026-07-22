import QtQuick 2.0
import Sailfish.Silica 1.0

// Выбор области удаления сертификата: только сертификат или сертификат вместе с
// ключами. По выбору испускает chosen(keysToo) и закрывается (как PinPadPage).
//
// Удаление требует входа по PIN-коду (приватные ключи видны только после входа).
// Пока не вошли — предупреждаем, что у сертификата может быть закрытый ключ,
// невидимый без входа, и предлагаем ввести PIN-код (отдельным экраном). После
// входа объекты перечитываются, и наличие ключа (hasKey) определяется честно.
Page {
    id: page
    objectName: "deleteCertPage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string idHex: ""
    property string certName: ""
    property bool attempted: false   // пробовали войти → показать результат

    // Наличие ключа — живо из объектов сессии (после входа ключи становятся видны).
    property bool hasKey: {
        var objs = tokenSession.objects
        for (var i = 0; i < objs.length; ++i) {
            if (objs[i].idHex === page.idHex)
                return objs[i].hasKey ? true : false
        }
        return false
    }

    signal chosen(bool keysToo)

    function pick(keysToo) {
        page.chosen(keysToo)
        pageStack.pop()
    }

    function enterPin() {
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            acceptText: qsTr("Log in")
        })
        pad.entered.connect(function(pin) {
            page.attempted = true
            tokenSession.login(page.slotId, pin)
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader { title: qsTr("Delete certificate") }

            // --- Вошли: выбор области удаления ---
            Label {
                visible: tokenSession.loggedIn
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: page.certName.length > 0
                      ? qsTr("Delete “%1” — what should be removed?").arg(page.certName)
                      : qsTr("What should be removed?")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Button {
                visible: tokenSession.loggedIn
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Only the certificate")
                onClicked: page.pick(false)
            }

            Button {
                visible: tokenSession.loggedIn && page.hasKey
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Certificate and its keys")
                onClicked: page.pick(true)
            }

            Label {
                visible: tokenSession.loggedIn && page.hasKey
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Deleting the keys is irreversible — the private key cannot be recovered.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            // --- Не вошли: предупреждение о возможном скрытом ключе + вход ---
            Label {
                visible: !tokenSession.loggedIn
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("This certificate may have a private key that stays hidden until you enter the PIN. Enter the PIN to see and remove it too.")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Button {
                visible: !tokenSession.loggedIn
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Checking…") : qsTr("Enter PIN")
                enabled: !tokenSession.busy
                onClicked: page.enterPin()
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: tokenSession.busy
                visible: tokenSession.busy
                size: BusyIndicatorSize.Medium
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                visible: page.attempted && !tokenSession.loggedIn && !tokenSession.busy
                         && tokenSession.outcome !== 0
                text: tokenSession.result
                color: tokenSession.outcome === 1 ? "#4caf50" : "#f44336"
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
