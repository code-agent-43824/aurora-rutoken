import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    objectName: "tokensPage"
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Diagnostics")
                onClicked: pageStack.push(Qt.resolvedUrl("DiagnosticsPage.qml"))
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: tokenWatcher.refresh()
            }
        }

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Rutoken")
                description: tokenWatcher.status
            }

            // Пустое состояние: подсказка, что список обновляется сам.
            Column {
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingLarge
                visible: tokenWatcher.tokens.length === 0

                Item { width: 1; height: Theme.itemSizeLarge }

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: qsTr("Connect a Rutoken over USB or hold it near the NFC antenna")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeLarge
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: qsTr("The list updates automatically")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Repeater {
                model: tokenWatcher.tokens

                delegate: Column {
                    width: content.width
                    spacing: Theme.paddingSmall

                    Row {
                        x: Theme.horizontalPageMargin
                        width: content.width - 2 * Theme.horizontalPageMargin
                        spacing: Theme.paddingMedium

                        Rectangle {
                            id: badge
                            anchors.verticalCenter: title.verticalCenter
                            width: badgeLabel.width + 2 * Theme.paddingMedium
                            height: badgeLabel.height + Theme.paddingSmall
                            radius: Theme.paddingSmall
                            color: modelData.connection === "NFC"
                                   ? "#3949ab"
                                   : (modelData.connection === "USB" ? "#00796b" : "#616161")
                            Label {
                                id: badgeLabel
                                anchors.centerIn: parent
                                text: modelData.connection.length > 0 ? modelData.connection : qsTr("?")
                                color: "white"
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.bold: true
                            }
                        }

                        Label {
                            id: title
                            width: parent.width - badge.width - Theme.paddingMedium
                            text: modelData.label.length > 0 ? modelData.label : qsTr("Rutoken")
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeLarge
                            truncationMode: TruncationMode.Fade
                        }
                    }

                    Label {
                        x: Theme.horizontalPageMargin
                        width: content.width - 2 * Theme.horizontalPageMargin
                        text: qsTr("Serial number: %1").arg(modelData.serial.length > 0 ? modelData.serial : "—")
                        color: Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        textFormat: Text.PlainText
                    }

                    Label {
                        x: Theme.horizontalPageMargin
                        width: content.width - 2 * Theme.horizontalPageMargin
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: {
                            var parts = []
                            if (modelData.model.length > 0)
                                parts.push(modelData.model)
                            if (modelData.firmware.length > 0)
                                parts.push(qsTr("firmware %1").arg(modelData.firmware))
                            if (modelData.flags.length > 0)
                                parts.push(modelData.flags)
                            return parts.join("  •  ")
                        }
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }

                    Label {
                        x: Theme.horizontalPageMargin
                        width: content.width - 2 * Theme.horizontalPageMargin
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: qsTr("reader: %1").arg(modelData.slotName.length > 0 ? modelData.slotName : "—")
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeTiny
                    }

                    Separator {
                        width: content.width - 2 * Theme.horizontalPageMargin
                        x: Theme.horizontalPageMargin
                        color: Theme.secondaryColor
                        horizontalAlignment: Qt.AlignHCenter
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
