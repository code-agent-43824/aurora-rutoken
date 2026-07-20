import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "exportCertificatePage"
    allowedOrientations: Orientation.All

    property string derB64: ""
    property string suggestedName: ""
    property string result: ""

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Export certificate")
            }

            ComboBox {
                id: formatCombo
                width: parent.width
                label: qsTr("Format")
                menu: ContextMenu {
                    MenuItem { text: qsTr("PEM (text)") }
                    MenuItem { text: qsTr("DER (binary)") }
                }
            }

            TextField {
                id: nameField
                width: parent.width
                label: qsTr("File name")
                placeholderText: page.suggestedName.length > 0 ? page.suggestedName : qsTr("certificate")
                text: page.suggestedName
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
            }

            TextField {
                id: dirField
                width: parent.width
                label: qsTr("Folder")
                placeholderText: qsTr("Save folder")
                text: tokenSession.defaultExportDir()
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("The file extension (.pem/.der) is added automatically. The private key is never exported.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Save")
                onClicked: {
                    Qt.inputMethod.commit()
                    var fmt = formatCombo.currentIndex === 1 ? "der" : "pem"
                    page.result = tokenSession.exportCertificate(page.derB64, fmt,
                                                                 dirField.text, nameField.text)
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.result.length > 0
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: page.result
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
