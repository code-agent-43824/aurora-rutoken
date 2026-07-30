import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "cryptoProPage"
    allowedOrientations: Orientation.All
    property bool initialRefreshStarted: false

    onStatusChanged: {
        if (status === PageStatus.Active && !initialRefreshStarted) {
            initialRefreshStarted = true
            cryptoProSession.refresh()
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Refresh")
                enabled: !cryptoProSession.busy
                onClicked: cryptoProSession.refresh()
            }
        }

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("CryptoPro CSP")
                description: cryptoProSession.status
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: cryptoProSession.busy
                size: BusyIndicatorSize.Medium
            }

            Label {
                visible: cryptoProSession.available && cryptoProSession.libraryPath.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WrapAnywhere
                textFormat: Text.PlainText
                text: qsTr("Library: %1").arg(cryptoProSession.libraryPath)
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeTiny
            }

            Label {
                visible: !cryptoProSession.busy && !cryptoProSession.available
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("CryptoPro CSP is optional and is not included with the application")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeMedium
            }

            SectionHeader {
                visible: cryptoProSession.available
                text: qsTr("Rutoken containers")
            }

            Label {
                visible: cryptoProSession.available && !cryptoProSession.busy
                         && cryptoProSession.containers.length === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("No Rutoken containers found through CryptoPro CSP")
                color: Theme.secondaryColor
            }

            Repeater {
                model: cryptoProSession.containers
                delegate: Column {
                    width: content.width
                    spacing: Theme.paddingSmall

                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                        text: modelData.name.length > 0 ? modelData.name : qsTr("Unnamed container")
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: qsTr("provider types %1 · certificates: %2")
                              .arg(modelData.providerTypesText)
                              .arg(modelData.certificateCount)
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }

            SectionHeader {
                visible: cryptoProSession.available
                text: qsTr("Linked certificates")
            }

            Label {
                visible: cryptoProSession.available && !cryptoProSession.busy
                         && cryptoProSession.certificates.length === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("No linked certificates found in the personal store")
                color: Theme.secondaryColor
            }

            Repeater {
                model: cryptoProSession.certificates
                delegate: BackgroundItem {
                    width: content.width
                    height: certColumn.height + Theme.paddingMedium
                    onClicked: pageStack.push(Qt.resolvedUrl("CryptoProCertificatePage.qml"), {
                        certificate: modelData
                    })

                    Column {
                        id: certColumn
                        width: parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingSmall

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            truncationMode: TruncationMode.Fade
                            textFormat: Text.PlainText
                            text: modelData.subject.length > 0 ? modelData.subject : qsTr("Certificate")
                            color: modelData.expired ? Theme.secondaryColor : Theme.highlightColor
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            wrapMode: Text.WrapAnywhere
                            textFormat: Text.PlainText
                            text: qsTr("Container: %1").arg(modelData.container)
                            color: Theme.primaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }
                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            wrapMode: Text.Wrap
                            text: modelData.privateKeyAvailable
                                  ? qsTr("Private key is available")
                                  : qsTr("Private key is unavailable")
                            color: modelData.privateKeyAvailable
                                   ? Theme.secondaryHighlightColor : Theme.errorColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }
                        Label {
                            visible: modelData.exactDuplicateCount > 1
                                     || modelData.containerCertificateCount > 1
                                     || modelData.metadataConflict
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            wrapMode: Text.Wrap
                            text: {
                                var notes = []
                                if (modelData.exactDuplicateCount > 1)
                                    notes.push(qsTr("exact DER copies: %1").arg(modelData.exactDuplicateCount))
                                if (modelData.containerCertificateCount > 1)
                                    notes.push(qsTr("different certificates for this container: %1")
                                               .arg(modelData.containerCertificateCount))
                                if (modelData.metadataConflict)
                                    notes.push(qsTr("metadata conflict"))
                                return notes.join(" · ")
                            }
                            color: Theme.errorColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator {}
    }
}
