import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    objectName: "settingsPage"
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width

            PageHeader {
                title: qsTr("Settings")
            }

            TextSwitch {
                width: parent.width
                text: qsTr("Use CryptoPro CSP")
                description: qsTr("When disabled, CryptoPro libraries are not loaded")
                checked: appSettings.cryptoProEnabled
                onClicked: appSettings.cryptoProEnabled = checked
            }
        }

        VerticalScrollDecorator {}
    }
}
