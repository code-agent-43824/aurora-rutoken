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

    // Живая метка. USB: ищем токен по slotId в списке TokenWatcher (перевычисляется
    // по tokensChanged — после смены метки + refresh заголовок обновляется). NFC:
    // берём метку из снимка nfcToken (после смены по NFC она обновляется через
    // setNfcLabel — токен уже убран, живого чтения нет).
    property string curLabel: {
        if (page.connection === "NFC") {
            return (tokenSession.nfcToken.label && tokenSession.nfcToken.label.length > 0)
                   ? tokenSession.nfcToken.label : page.tokenLabel
        }
        var ts = tokenWatcher.tokens
        for (var i = 0; i < ts.length; ++i) {
            if (ts[i].slotId === page.slotId)
                return ts[i].label
        }
        return page.tokenLabel
    }

    // Число объектов: USB — живые из сессии, NFC — снимок (nfcObjects).
    property int objectCount: page.connection === "NFC"
            ? tokenSession.nfcObjects.length : tokenSession.objects.length

    function openPinPad() {
        if (tokenSession.busy)
            return
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            subtitle: page.curLabel.length > 0 ? page.curLabel : qsTr("Rutoken"),
            acceptText: qsTr("Log in")
        })
        pad.entered.connect(function(pin) {
            tokenSession.login(page.slotId, pin)
        })
    }

    // Сертификаты видны без входа — читаем их сразу при открытии деталей (USB).
    // Для NFC живого чтения нет (токен не поднесён) — показываем снимок объектов.
    Component.onCompleted: if (page.connection !== "NFC") tokenSession.preview(page.slotId)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        // Управление PIN (v0.5): смена PIN пользователя/администратора и
        // разблокировка PIN пользователя администратором; смена метки токена.
        // Одно меню для USB и NFC (у NFC операции идут через доп. поднесение —
        // connection пробрасывается в целевые экраны).
        PullDownMenu {
            MenuItem {
                text: qsTr("Change token label")
                onClicked: pageStack.push(Qt.resolvedUrl("TokenLabelPage.qml"),
                                          { slotId: page.slotId, currentLabel: page.curLabel,
                                            connection: page.connection })
            }
            MenuItem {
                text: qsTr("Unblock user PIN")
                onClicked: pageStack.push(Qt.resolvedUrl("PinChangePage.qml"),
                                          { slotId: page.slotId, mode: "unblock",
                                            connection: page.connection })
            }
            MenuItem {
                text: qsTr("Change admin PIN")
                onClicked: pageStack.push(Qt.resolvedUrl("PinChangePage.qml"),
                                          { slotId: page.slotId, mode: "so",
                                            connection: page.connection })
            }
            MenuItem {
                text: qsTr("Change user PIN")
                onClicked: pageStack.push(Qt.resolvedUrl("PinChangePage.qml"),
                                          { slotId: page.slotId, mode: "user",
                                            connection: page.connection })
            }
        }

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: page.curLabel.length > 0 ? page.curLabel : qsTr("Rutoken")
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

            // Вход по PIN — только для USB (у NFC нет постоянного входа; объекты
            // берутся из снимка, а операции идут через доп. поднесение).
            SectionHeader {
                visible: page.connection !== "NFC"
                text: qsTr("User PIN login")
            }

            // Не вошли — открыть отдельный экран ввода PIN (цифровая клавиатура).
            Button {
                visible: page.connection !== "NFC" && !tokenSession.loggedIn
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Checking…") : qsTr("Enter PIN")
                enabled: !tokenSession.busy
                onClicked: page.openPinPad()
            }

            // Вошли — статус и выход.
            Label {
                visible: page.connection !== "NFC" && tokenSession.loggedIn
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Logged in — the PIN is remembered")
                color: "#4caf50"
                font.pixelSize: Theme.fontSizeMedium
            }

            Button {
                visible: page.connection !== "NFC" && tokenSession.loggedIn
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Log out")
                enabled: !tokenSession.busy
                onClicked: tokenSession.logout()
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: tokenSession.busy
                visible: page.connection !== "NFC" && tokenSession.busy
                size: BusyIndicatorSize.Medium
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                visible: page.connection !== "NFC" && !tokenSession.busy && tokenSession.outcome !== 0
                text: tokenSession.result
                color: tokenSession.outcome === 1 ? "#4caf50" : "#f44336"
                font.pixelSize: Theme.fontSizeMedium
            }

            // Объекты токена: для USB — живые (после входа), для NFC — снимок.
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !tokenSession.busy && page.objectCount > 0
                text: qsTr("Token objects (%1)").arg(page.objectCount)
                onClicked: pageStack.push(Qt.resolvedUrl("ObjectsPage.qml"), {
                    slotId: page.slotId,
                    tokenLabel: page.curLabel,
                    connection: page.connection
                })
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                visible: page.connection !== "NFC"
                text: qsTr("The PIN is kept in memory until you log out, unplug the USB token, or close the app.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
