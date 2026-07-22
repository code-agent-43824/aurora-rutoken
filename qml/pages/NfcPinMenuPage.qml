import QtQuick 2.0
import Sailfish.Silica 1.0

// Выбор PIN-операции по NFC. Запускает общий PinChangePage в режиме NFC:
// сначала собираются все PIN (без токена), затем всё выполняется за одно
// короткое поднесение. Предварительное «подключение» не требуется.
Page {
    id: page
    objectName: "nfcPinMenuPage"
    allowedOrientations: Orientation.All

    function open(mode) {
        pageStack.push(Qt.resolvedUrl("PinChangePage.qml"),
                       { mode: mode, connection: "NFC" })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader { title: qsTr("PIN over NFC") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Choose an operation. You enter all PINs first, then hold the token once to run it.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Change user PIN")
                onClicked: page.open("user")
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Change admin PIN")
                onClicked: page.open("so")
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Unblock user PIN")
                onClicked: page.open("unblock")
            }
        }

        VerticalScrollDecorator {}
    }
}
