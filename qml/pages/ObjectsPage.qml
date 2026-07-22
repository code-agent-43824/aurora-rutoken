import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "objectsPage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string tokenLabel: ""
    property string connection: ""
    property bool deleteAttempted: false   // показывать результат только после удаления

    // Для NFC показываем сохранённый снимок объектов (можно вернуться к
    // сертификатам без повторного поднесения); для USB — живые объекты сессии.
    property var objectsModel: page.connection === "NFC" ? tokenSession.nfcObjects
                                                          : tokenSession.objects

    function certTitle(o) {
        if (o.parsed && o.commonName && o.commonName.length > 0)
            return o.commonName
        if (o.label && o.label.length > 0)
            return o.label
        return ""
    }

    // Удаление записи долгим нажатием (пока по USB: приватные ключи видны только
    // после входа). Сертификат — всегда спрашиваем область (только сертификат /
    // сертификат+ключи) через DeleteCertPage. Ключ — сразу, с отсрочкой RemorsePopup.
    function confirmDelete(m) {
        if (page.connection === "NFC")
            return
        if (!m.idHex || m.idHex.length === 0)
            return
        if (m.kind === "certificate") {
            var id = m.idHex
            var dlg = pageStack.push(Qt.resolvedUrl("DeleteCertPage.qml"), {
                certName: page.certTitle(m),
                hasKey: m.hasKey ? true : false
            })
            dlg.chosen.connect(function(keysToo) {
                page.deleteAttempted = true
                tokenSession.deleteObjectsCached(page.slotId, id, keysToo)
            })
        } else {
            remorse.execute(qsTr("Deleting the key"), function() {
                page.deleteAttempted = true
                tokenSession.deleteObjectsCached(page.slotId, m.idHex, true)
            })
        }
    }

    RemorsePopup { id: remorse }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Import certificate")
                onClicked: pageStack.push(Qt.resolvedUrl("ImportCertificatePage.qml"), {
                    slotId: page.slotId,
                    connection: page.connection
                })
            }
            MenuItem {
                text: qsTr("Generate key pair")
                onClicked: pageStack.push(Qt.resolvedUrl("GenerateKeyPage.qml"), {
                    slotId: page.slotId,
                    connection: page.connection
                })
            }
        }

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: page.tokenLabel.length > 0 ? page.tokenLabel : qsTr("Objects")
                description: qsTr("Objects via PKCS#11")
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: tokenSession.busy
                visible: tokenSession.busy
                size: BusyIndicatorSize.Medium
            }

            // Результат удаления (успех виден и по исчезновению записи из списка).
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                visible: page.deleteAttempted && !tokenSession.busy && tokenSession.outcome !== 0
                text: tokenSession.result
                color: tokenSession.outcome === 1 ? "#4caf50" : "#f44336"
                font.pixelSize: Theme.fontSizeSmall
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.objectsModel.length === 0
                wrapMode: Text.Wrap
                text: qsTr("No certificates or keys found on the token")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeMedium
            }

            // Подсказка про удаление (только USB — по NFC удаление появится позже).
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.connection !== "NFC" && page.objectsModel.length > 0
                wrapMode: Text.Wrap
                text: qsTr("Press and hold an item to delete it (with its keys)")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Repeater {
                model: page.objectsModel

                delegate: BackgroundItem {
                    width: content.width
                    height: card.height + Theme.paddingMedium
                    // Тап открывает сертификат; долгое нажатие — удалить (USB).
                    onClicked: {
                        if (modelData.kind === "certificate")
                            pageStack.push(Qt.resolvedUrl("CertificatePage.qml"), {
                                commonName: modelData.commonName ? modelData.commonName : "",
                                issuer: modelData.issuer ? modelData.issuer : "",
                                expiry: modelData.expiry ? modelData.expiry : "",
                                parsed: modelData.parsed ? modelData.parsed : false,
                                idText: modelData.idText ? modelData.idText : "",
                                idHex: modelData.idHex ? modelData.idHex : "",
                                label: modelData.label ? modelData.label : "",
                                source: modelData.source ? modelData.source : "",
                                derB64: modelData.derB64 ? modelData.derB64 : "",
                                hasKey: modelData.hasKey ? modelData.hasKey : false,
                                keysKnown: modelData.keysKnown ? modelData.keysKnown : false,
                                slotId: page.slotId,
                                connection: page.connection
                            })
                    }
                    onPressAndHold: page.confirmDelete(modelData)

                    Column {
                        id: card
                        width: parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingSmall

                        Row {
                            x: Theme.horizontalPageMargin
                            width: card.width - 2 * Theme.horizontalPageMargin
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
                                text: modelData.kind === "certificate"
                                      ? page.certTitle(modelData)
                                      : (modelData.label.length > 0 ? modelData.label : "")
                                color: Theme.highlightColor
                                font.pixelSize: Theme.fontSizeMedium
                                truncationMode: TruncationMode.Fade
                            }
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: card.width - 2 * Theme.horizontalPageMargin
                            visible: modelData.kind === "certificate"
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            text: {
                                var parts = []
                                if (modelData.kind === "certificate") {
                                    if (modelData.parsed) {
                                        if (modelData.issuer && modelData.issuer.length > 0)
                                            parts.push(qsTr("issuer: %1").arg(modelData.issuer))
                                        if (modelData.expiry && modelData.expiry.length > 0)
                                            parts.push(qsTr("expires: %1").arg(modelData.expiry))
                                    } else if (modelData.idText && modelData.idText.length > 0) {
                                        parts.push(qsTr("ID: %1").arg(modelData.idText))
                                    }
                                    parts.push(modelData.source)
                                }
                                return parts.join("  •  ")
                            }
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: card.width - 2 * Theme.horizontalPageMargin
                            visible: modelData.kind === "key"
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            text: {
                                var parts = []
                                if (modelData.kind === "key") {
                                    parts.push(qsTr("ID: %1").arg(modelData.idText && modelData.idText.length > 0 ? modelData.idText : "—"))
                                    if (modelData.keyType && modelData.keyType.length > 0)
                                        parts.push(modelData.keyType)
                                    if (modelData.keyClass && modelData.keyClass.length > 0)
                                        parts.push(modelData.keyClass)
                                    parts.push(modelData.source)
                                }
                                return parts.join("  •  ")
                            }
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: card.width - 2 * Theme.horizontalPageMargin
                            visible: modelData.kind === "certificate" && !modelData.keysKnown
                            text: qsTr("keys are shown after PIN login")
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.italic: true
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: card.width - 2 * Theme.horizontalPageMargin
                            visible: modelData.kind === "certificate" && modelData.keysKnown && !modelData.hasKey
                            text: qsTr("certificate without a key (standalone)")
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.italic: true
                        }

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
                            width: card.width - 2 * Theme.horizontalPageMargin
                            x: Theme.horizontalPageMargin
                            color: Theme.secondaryColor
                            horizontalAlignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
