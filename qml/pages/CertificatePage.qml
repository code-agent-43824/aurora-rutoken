import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "certificatePage"
    allowedOrientations: Orientation.All

    property string commonName: ""
    property string issuer: ""
    property string expiry: ""
    property bool parsed: false
    property string idText: ""
    property string label: ""
    property string source: ""
    property string derB64: ""
    property bool hasKey: false
    property bool keysKnown: false

    function title() {
        if (page.parsed && page.commonName.length > 0)
            return page.commonName
        if (page.label.length > 0)
            return page.label
        return qsTr("Certificate")
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Export certificate")
                onClicked: pageStack.push(Qt.resolvedUrl("ExportCertificatePage.qml"), {
                    derB64: page.derB64,
                    suggestedName: page.title()
                })
            }
        }

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: page.title()
                description: qsTr("Certificate — via PKCS#11")
            }

            DetailItem {
                label: qsTr("Common Name")
                value: page.parsed && page.commonName.length > 0 ? page.commonName : "—"
            }
            DetailItem {
                label: qsTr("Issuer")
                value: page.parsed && page.issuer.length > 0 ? page.issuer : "—"
            }
            DetailItem {
                label: qsTr("Expires")
                value: page.parsed && page.expiry.length > 0 ? page.expiry : "—"
            }
            DetailItem {
                label: qsTr("CKA_LABEL")
                value: page.label.length > 0 ? page.label : "—"
            }
            DetailItem {
                label: qsTr("CKA_ID")
                value: page.idText.length > 0 ? page.idText : "—"
            }
            DetailItem {
                label: qsTr("Key on token")
                value: !page.keysKnown ? qsTr("unknown until PIN login")
                       : (page.hasKey ? qsTr("yes") : qsTr("no (standalone)"))
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !page.parsed
                wrapMode: Text.Wrap
                text: qsTr("The X.509 body could not be parsed; showing token attributes.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Item { width: 1; height: Theme.paddingLarge }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Pull down to export the certificate (without the private key).")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
