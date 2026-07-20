import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "objectsPage"
    allowedOrientations: Orientation.All

    property string tokenLabel: ""
    property string connection: ""

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: page.tokenLabel.length > 0 ? page.tokenLabel : qsTr("Objects")
                description: qsTr("Objects via PKCS#11")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: tokenSession.objects.length === 0
                wrapMode: Text.Wrap
                text: qsTr("No certificates or keys found on the token")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Repeater {
                model: tokenSession.objects

                delegate: Column {
                    width: content.width
                    spacing: Theme.paddingSmall

                    // Заголовок верхнего уровня: сертификат или ключ-сирота.
                    Row {
                        x: Theme.horizontalPageMargin
                        width: content.width - 2 * Theme.horizontalPageMargin
                        spacing: Theme.paddingMedium

                        Rectangle {
                            id: kindBadge
                            anchors.verticalCenter: kindTitle.verticalCenter
                            width: kindBadgeLabel.width + 2 * Theme.paddingMedium
                            height: kindBadgeLabel.height + Theme.paddingSmall
                            radius: Theme.paddingSmall
                            color: modelData.kind === "certificate" ? "#00695c" : "#5d4037"
                            Label {
                                id: kindBadgeLabel
                                anchors.centerIn: parent
                                text: modelData.kind === "certificate" ? qsTr("CERT") : qsTr("KEY")
                                color: "white"
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.bold: true
                            }
                        }

                        Label {
                            id: kindTitle
                            width: parent.width - kindBadge.width - Theme.paddingMedium
                            text: modelData.label.length > 0 ? modelData.label : qsTr("(no label)")
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeMedium
                            truncationMode: TruncationMode.Fade
                        }
                    }

                    Label {
                        x: Theme.horizontalPageMargin
                        width: content.width - 2 * Theme.horizontalPageMargin
                        textFormat: Text.PlainText
                        text: {
                            var parts = []
                            parts.push(qsTr("ID: %1").arg(modelData.idHex.length > 0 ? modelData.idHex : "—"))
                            if (modelData.kind === "key" && modelData.keyType && modelData.keyType.length > 0)
                                parts.push(modelData.keyType)
                            if (modelData.kind === "key" && modelData.keyClass && modelData.keyClass.length > 0)
                                parts.push(modelData.keyClass)
                            parts.push(modelData.source)
                            return parts.join("  •  ")
                        }
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        wrapMode: Text.Wrap
                    }

                    // Для сертификата: есть ключ или он сам по себе.
                    Label {
                        x: Theme.horizontalPageMargin
                        width: content.width - 2 * Theme.horizontalPageMargin
                        visible: modelData.kind === "certificate" && !modelData.hasKey
                        text: qsTr("certificate without a key (standalone)")
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        font.italic: true
                    }

                    // Вложенные ключи сертификата (второй уровень).
                    Repeater {
                        model: modelData.kind === "certificate" ? modelData.keys : []

                        delegate: Row {
                            x: 2 * Theme.horizontalPageMargin
                            width: content.width - 3 * Theme.horizontalPageMargin
                            spacing: Theme.paddingSmall

                            Label {
                                text: "↳"
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            Label {
                                width: parent.width - Theme.paddingLarge
                                textFormat: Text.PlainText
                                text: {
                                    var p = [modelData.keyClass]
                                    if (modelData.keyType && modelData.keyType.length > 0)
                                        p.push(modelData.keyType)
                                    if (modelData.label && modelData.label.length > 0)
                                        p.push(modelData.label)
                                    return p.join("  •  ")
                                }
                                color: Theme.primaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                wrapMode: Text.Wrap
                            }
                        }
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
