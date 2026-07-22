import QtQuick 2.0
import Sailfish.Silica 1.0

// Выбор области удаления сертификата: только сертификат или сертификат вместе с
// ключами. По выбору испускает chosen(keysToo) и закрывается (как PinPadPage).
// Если у сертификата нет ключей — показывается только «Только сертификат».
Page {
    id: page
    objectName: "deleteCertPage"
    allowedOrientations: Orientation.All

    property string certName: ""
    property bool hasKey: false

    signal chosen(bool keysToo)

    function pick(keysToo) {
        page.chosen(keysToo)
        pageStack.pop()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader { title: qsTr("Delete certificate") }

            Label {
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
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Only the certificate")
                onClicked: page.pick(false)
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.hasKey
                text: qsTr("Certificate and its keys")
                onClicked: page.pick(true)
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                visible: page.hasKey
                text: qsTr("Deleting the keys is irreversible — the private key cannot be recovered.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
