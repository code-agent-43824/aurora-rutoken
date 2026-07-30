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
    property string idHex: ""
    property string label: ""
    property string source: ""
    property string derB64: ""
    property double notAfterMs: 0
    property double currentTimeMs: Date.now()
    property bool expired: page.notAfterMs > 0 && page.currentTimeMs > page.notAfterMs
    property bool hasKey: false
    property bool keysKnown: false
    property bool cryptoPro: false
    property string container: ""
    property var slotId: 0
    property string connection: ""

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: page.currentTimeMs = Date.now()
    }

    function title() {
        if (page.parsed && page.commonName.length > 0)
            return page.commonName
        if (page.label.length > 0)
            return page.label
        return qsTr("Certificate")
    }

    // Удаление сертификата: всегда спрашиваем область (только сертификат /
    // сертификат+ключи). USB — через DeleteCertPage, после удаления закрываем
    // детали. NFC — через NfcDeletePage (собираем область+PIN-код, затем одно
    // поднесение); детали остаются, список обновится по снимку.
    function doDelete() {
        if (page.connection === "NFC") {
            pageStack.push(Qt.resolvedUrl("NfcDeletePage.qml"), {
                kind: "certificate",
                idHex: page.idHex,
                certName: page.title(),
                hasKey: page.hasKey,
                keysKnown: page.keysKnown,
                slotId: page.slotId
            })
            return
        }
        var dlg = pageStack.push(Qt.resolvedUrl("DeleteCertPage.qml"), {
            certName: page.title(),
            idHex: page.idHex,
            slotId: page.slotId
        })
        dlg.chosen.connect(function(keysToo, noLogin) {
            if (noLogin)
                tokenSession.deleteCertPublic(page.slotId, page.idHex)
            else
                tokenSession.deleteObjectsCached(page.slotId, page.idHex, keysToo)
            pageStack.pop()
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height

        PullDownMenu {
            MenuItem {
                visible: !page.expired && page.idHex.length > 0
                         && page.derB64.length > 0 && page.hasKey
                text: qsTr("Sign a file")
                onClicked: pageStack.push(Qt.resolvedUrl("SignFilePage.qml"), {
                    slotId: page.slotId,
                    idHex: page.idHex,
                    certificateDerB64: page.derB64,
                    certificateName: page.title(),
                    connection: page.connection
                })
            }
            // Запрос на сертификат для ключевой пары этого сертификата (USB и NFC).
            MenuItem {
                visible: page.idHex.length > 0
                text: qsTr("Create certificate request")
                onClicked: pageStack.push(Qt.resolvedUrl("CsrPage.qml"), {
                    slotId: page.slotId,
                    idHex: page.idHex,
                    keyName: page.title(),
                    connection: page.connection
                })
            }
            // Удаление сертификата (USB и NFC).
            MenuItem {
                visible: page.idHex.length > 0
                text: qsTr("Delete certificate")
                onClicked: page.doDelete()
            }
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
                description: page.cryptoPro ? qsTr("Certificate — via CryptoPro CSP")
                                            : qsTr("Certificate — via PKCS#11")
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
                visible: !page.cryptoPro
                label: qsTr("CKA_LABEL")
                value: page.label.length > 0 ? page.label : "—"
            }
            DetailItem {
                label: page.cryptoPro ? qsTr("Serial number") : qsTr("CKA_ID")
                value: page.idText.length > 0 ? page.idText : "—"
            }
            DetailItem {
                visible: page.cryptoPro
                label: qsTr("Container")
                value: page.container.length > 0 ? page.container : "—"
            }
            DetailItem {
                label: qsTr("Key on Rutoken")
                value: !page.keysKnown ? qsTr("unknown until PIN login")
                       : (page.hasKey ? qsTr("yes") : qsTr("no (standalone)"))
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !page.parsed
                wrapMode: Text.Wrap
                text: qsTr("The X.509 body could not be parsed; showing Rutoken attributes.")
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
