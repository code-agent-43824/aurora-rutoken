import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "tokensPage"
    allowedOrientations: Orientation.All

    // Живой список — только USB-токены, кроме логически отключённых (по серийнику).
    // NFC подключается отдельным мастером (эфемерный пункт ниже).
    property var usbTokens: {
        var out = []
        var ts = tokenWatcher.tokens
        var sup = tokenSession.suppressedUsb
        for (var i = 0; i < ts.length; ++i) {
            if (ts[i].connection === "USB" && sup.indexOf(ts[i].serial) < 0)
                out.push(ts[i])
        }
        return out
    }

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

            SectionHeader { text: qsTr("USB") }

            // Пустое состояние для USB: подсказка, что список обновляется сам.
            Column {
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium
                visible: page.usbTokens.length === 0

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: qsTr("Connect a Rutoken over USB — it appears here automatically")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeMedium
                }
            }

            Repeater {
                model: page.usbTokens

                delegate: BackgroundItem {
                    width: content.width
                    height: cardColumn.height + Theme.paddingMedium

                    onClicked: {
                        tokenSession.clear()
                        pageStack.push(Qt.resolvedUrl("TokenDetailsPage.qml"), {
                            slotId: modelData.slotId,
                            tokenLabel: modelData.label,
                            serial: modelData.serial,
                            tokenModel: modelData.model,
                            manufacturer: modelData.manufacturer,
                            connection: modelData.connection,
                            firmware: modelData.firmware,
                            hardware: modelData.hardware,
                            flags: modelData.flags,
                            slotName: modelData.slotName
                        })
                    }

                    Column {
                        id: cardColumn
                        width: parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingSmall

                        Row {
                            x: Theme.horizontalPageMargin
                            width: cardColumn.width - 2 * Theme.horizontalPageMargin
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
                            width: cardColumn.width - 2 * Theme.horizontalPageMargin
                            text: qsTr("Serial number: %1").arg(modelData.serial.length > 0 ? modelData.serial : "—")
                            color: Theme.primaryColor
                            font.pixelSize: Theme.fontSizeMedium
                            textFormat: Text.PlainText
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: cardColumn.width - 2 * Theme.horizontalPageMargin
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
                            width: cardColumn.width - 2 * Theme.horizontalPageMargin
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            text: qsTr("reader: %1").arg(modelData.slotName.length > 0 ? modelData.slotName : "—")
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeTiny
                        }

                        // Логически отключить USB-токен: скрыть из списка до
                        // физического переподключения (кнопка не мешает тапу по карточке).
                        Button {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.horizontalPageMargin
                            text: qsTr("Disconnect")
                            onClicked: {
                                if (tokenSession.loggedInSlot === modelData.slotId)
                                    tokenSession.logout()
                                tokenSession.suppressUsb(modelData.serial)
                            }
                        }
                    }
                }
            }

            SectionHeader { text: qsTr("NFC") }

            // Логически подключённый NFC-токен: снимок объектов сохранён — можно
            // вернуться к его сертификатам без повторного поднесения.
            BackgroundItem {
                visible: tokenSession.nfcConnected
                width: content.width
                height: nfcTokCol.height + Theme.paddingMedium
                onClicked: pageStack.push(Qt.resolvedUrl("ObjectsPage.qml"), {
                    connection: "NFC",
                    slotId: tokenSession.nfcToken.slotId ? tokenSession.nfcToken.slotId : 0,
                    tokenLabel: (tokenSession.nfcToken.label && tokenSession.nfcToken.label.length > 0)
                                ? tokenSession.nfcToken.label : ""
                })
                Column {
                    id: nfcTokCol
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall

                    Row {
                        x: Theme.horizontalPageMargin
                        width: nfcTokCol.width - 2 * Theme.horizontalPageMargin
                        spacing: Theme.paddingMedium

                        Rectangle {
                            id: connBadge
                            anchors.verticalCenter: connTitle.verticalCenter
                            width: connBadgeLabel.width + 2 * Theme.paddingMedium
                            height: connBadgeLabel.height + Theme.paddingSmall
                            radius: Theme.paddingSmall
                            color: "#3949ab"
                            Label {
                                id: connBadgeLabel
                                anchors.centerIn: parent
                                text: qsTr("NFC")
                                color: "white"
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.bold: true
                            }
                        }
                        Label {
                            id: connTitle
                            width: parent.width - connBadge.width - Theme.paddingMedium
                            text: (tokenSession.nfcToken.label && tokenSession.nfcToken.label.length > 0)
                                  ? tokenSession.nfcToken.label : qsTr("Rutoken")
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeLarge
                            truncationMode: TruncationMode.Fade
                        }
                    }

                    Label {
                        x: Theme.horizontalPageMargin
                        width: nfcTokCol.width - 2 * Theme.horizontalPageMargin
                        textFormat: Text.PlainText
                        text: qsTr("connected via NFC — tap to open")
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }

                    Button {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        text: qsTr("Disconnect")
                        onClicked: tokenSession.disconnectNfc()
                    }
                }
            }

            // Эфемерный NFC-токен: не подключён, но «можно подключить». Тап
            // запускает мастер. Скрыт, если NFC-токен уже логически подключён
            // (работаем только с одним одновременно).
            BackgroundItem {
                visible: !tokenSession.nfcConnected
                width: content.width
                height: nfcCard.height + Theme.paddingMedium
                onClicked: {
                    tokenSession.clear()
                    pageStack.push(Qt.resolvedUrl("NfcConnectPage.qml"), { operation: "connect" })
                }
                Column {
                    id: nfcCard
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall

                    Row {
                        x: Theme.horizontalPageMargin
                        width: nfcCard.width - 2 * Theme.horizontalPageMargin
                        spacing: Theme.paddingMedium

                        Rectangle {
                            id: nfcBadge
                            anchors.verticalCenter: nfcTitle.verticalCenter
                            width: nfcBadgeLabel.width + 2 * Theme.paddingMedium
                            height: nfcBadgeLabel.height + Theme.paddingSmall
                            radius: Theme.paddingSmall
                            color: "#3949ab"
                            Label {
                                id: nfcBadgeLabel
                                anchors.centerIn: parent
                                text: qsTr("NFC")
                                color: "white"
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.bold: true
                            }
                        }
                        Label {
                            id: nfcTitle
                            width: parent.width - nfcBadge.width - Theme.paddingMedium
                            text: qsTr("Connect over NFC")
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeLarge
                            truncationMode: TruncationMode.Fade
                        }
                    }

                    Label {
                        x: Theme.horizontalPageMargin
                        width: nfcCard.width - 2 * Theme.horizontalPageMargin
                        wrapMode: Text.Wrap
                        text: qsTr("Tap and follow the steps: hold the token to the back cover")
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
