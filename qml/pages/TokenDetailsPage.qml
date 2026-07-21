import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "tokenDetailsPage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string tokenLabel: ""
    property string serial: ""
    property string tokenModel: ""
    property string manufacturer: ""
    property string connection: ""
    property string firmware: ""
    property string hardware: ""
    property string flags: ""
    property string slotName: ""

    function openPinPad() {
        if (tokenSession.busy)
            return
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            subtitle: page.tokenLabel.length > 0 ? page.tokenLabel : qsTr("Rutoken"),
            acceptText: qsTr("Log in")
        })
        pad.entered.connect(function(pin) {
            tokenSession.login(page.slotId, pin)
        })
    }

    // Сертификаты видны без входа — читаем их сразу при открытии деталей.
    Component.onCompleted: tokenSession.preview(page.slotId)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        // Управление PIN (v0.5): смена PIN пользователя/администратора и
        // разблокировка PIN пользователя администратором.
        PullDownMenu {
            MenuItem {
                text: qsTr("Unblock user PIN")
                onClicked: pageStack.push(Qt.resolvedUrl("PinChangePage.qml"),
                                          { slotId: page.slotId, mode: "unblock" })
            }
            MenuItem {
                text: qsTr("Change admin PIN")
                onClicked: pageStack.push(Qt.resolvedUrl("PinChangePage.qml"),
                                          { slotId: page.slotId, mode: "so" })
            }
            MenuItem {
                text: qsTr("Change user PIN")
                onClicked: pageStack.push(Qt.resolvedUrl("PinChangePage.qml"),
                                          { slotId: page.slotId, mode: "user" })
            }
        }

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: page.tokenLabel.length > 0 ? page.tokenLabel : qsTr("Rutoken")
                description: page.connection.length > 0 ? page.connection : qsTr("token")
            }

            DetailItem {
                label: qsTr("Serial number")
                value: page.serial.length > 0 ? page.serial : "—"
            }
            DetailItem {
                label: qsTr("Model")
                value: page.tokenModel.length > 0 ? page.tokenModel : "—"
            }
            DetailItem {
                label: qsTr("Manufacturer")
                value: page.manufacturer.length > 0 ? page.manufacturer : "—"
            }
            DetailItem {
                label: qsTr("Firmware / hardware")
                value: (page.firmware.length > 0 ? page.firmware : "—")
                       + " / " + (page.hardware.length > 0 ? page.hardware : "—")
            }
            DetailItem {
                label: qsTr("Reader")
                value: page.slotName.length > 0 ? page.slotName : "—"
            }
            DetailItem {
                label: qsTr("Flags")
                value: page.flags.length > 0 ? page.flags : "—"
            }

            SectionHeader { text: qsTr("User PIN login") }

            // Не вошли — открыть отдельный экран ввода PIN (цифровая клавиатура).
            Button {
                visible: !tokenSession.loggedIn
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Checking…") : qsTr("Enter PIN")
                enabled: !tokenSession.busy
                onClicked: page.openPinPad()
            }

            // Вошли — статус и выход.
            Label {
                visible: tokenSession.loggedIn
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Logged in — the PIN is remembered")
                color: "#4caf50"
                font.pixelSize: Theme.fontSizeMedium
            }

            Button {
                visible: tokenSession.loggedIn
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Log out")
                enabled: !tokenSession.busy
                onClicked: tokenSession.logout()
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
                visible: !tokenSession.busy && tokenSession.outcome !== 0
                text: tokenSession.result
                color: tokenSession.outcome === 1 ? "#4caf50" : "#f44336"
                font.pixelSize: Theme.fontSizeMedium
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !tokenSession.busy && tokenSession.objects.length > 0
                text: qsTr("Token objects (%1)").arg(tokenSession.objects.length)
                onClicked: pageStack.push(Qt.resolvedUrl("ObjectsPage.qml"), {
                    slotId: page.slotId,
                    tokenLabel: page.tokenLabel,
                    connection: page.connection
                })
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("The PIN is kept in memory until you log out, unplug the USB token, or close the app.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
