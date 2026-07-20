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

    function doLogin() {
        if (tokenSession.busy || pinField.text.length === 0)
            return
        Qt.inputMethod.commit()
        tokenSession.login(page.slotId, pinField.text)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

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

            TextField {
                id: pinField
                width: parent.width
                label: qsTr("User PIN")
                placeholderText: qsTr("Enter user PIN")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.doLogin()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Checking…") : qsTr("Log in")
                enabled: !tokenSession.busy && pinField.text.length > 0
                onClicked: page.doLogin()
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
                visible: !tokenSession.busy && tokenSession.outcome === 1
                text: qsTr("Token objects (%1)").arg(tokenSession.objects.length)
                onClicked: pageStack.push(Qt.resolvedUrl("ObjectsPage.qml"), {
                    tokenLabel: page.tokenLabel,
                    connection: page.connection
                })
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("The PIN is sent only to the token and is not stored.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
