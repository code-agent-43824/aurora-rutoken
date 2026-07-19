import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    objectName: "mainPage"
    allowedOrientations: Orientation.All

    // Заголовки строк диагностики по id из C++ (Diagnostics::rows)
    function rowTitle(id) {
        switch (id) {
        case "nfcsvc": return qsTr("NFC service (nfcd)")
        case "nfcinfo": return qsTr("NFC adapters")
        case "pcsclib": return qsTr("PC/SC library")
        case "context": return qsTr("PC/SC daemon (pcscd)")
        case "readers": return qsTr("PC/SC readers")
        case "pkcs11lib": return qsTr("Rutoken PKCS#11 library")
        case "pkcs11init": return qsTr("PKCS#11 initialization")
        case "pkcs11info": return qsTr("PKCS#11 information")
        case "pkcs11finalize": return qsTr("PKCS#11 finalization")
        default: return id
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Refresh")
                onClicked: diag.refresh()
            }
        }

        Column {
            id: content
            width: parent.width

            PageHeader {
                objectName: "pageHeader"
                title: qsTr("Rutoken Test")
                description: qsTr("PKCS#11 diagnostics — v0.0.3")
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: diag.running
                visible: diag.running
            }

            Repeater {
                model: diag.rows

                delegate: Item {
                    width: content.width
                    height: rowColumn.height + Theme.paddingLarge

                    Label {
                        id: mark
                        x: Theme.horizontalPageMargin
                        anchors.top: rowColumn.top
                        width: Theme.iconSizeSmall
                        text: modelData.ok === 1 ? "✓" : (modelData.ok === 0 ? "✕" : "⚠")
                        color: modelData.ok === 1 ? "#4caf50" : (modelData.ok === 0 ? "#f44336" : "#ff9800")
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    Column {
                        id: rowColumn
                        anchors.left: mark.right
                        anchors.leftMargin: Theme.paddingMedium
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        spacing: Theme.paddingSmall

                        Label {
                            width: parent.width
                            text: rowTitle(modelData.id)
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeMedium
                        }

                        Label {
                            width: parent.width
                            text: modelData.detail
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !diag.running && diag.rows.length === 0
                text: qsTr("Pull down to refresh")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        VerticalScrollDecorator {}
    }

    Component.onCompleted: diag.refresh()
}
