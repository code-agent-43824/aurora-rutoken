import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    objectName: "mainPage"
    allowedOrientations: Orientation.All

    PageHeader {
        id: pageHeader
        objectName: "pageHeader"
        title: qsTr("Rutoken Test")
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.horizontalPageMargin
        spacing: Theme.paddingMedium

        Label {
            objectName: "helloLabel"
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Hello Rutoken"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeExtraLarge
        }

        Label {
            objectName: "versionLabel"
            anchors.horizontalCenter: parent.horizontalCenter
            text: "v0.0.1"
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
