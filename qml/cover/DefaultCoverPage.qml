import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    objectName: "defaultCover"

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Rutoken")
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeSmall
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tokenWatcher.tokens.length
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeHuge
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: tokenWatcher.tokens.length === 1 ? qsTr("token") : qsTr("tokens")
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
        }
    }
}
