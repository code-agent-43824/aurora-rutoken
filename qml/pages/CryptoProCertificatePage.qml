import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "cryptoProCertificatePage"
    allowedOrientations: Orientation.All
    property var certificate: ({
        subject: "", issuer: "", serial: "", notBefore: "", notAfter: "",
        algorithm: "", provider: "", providerType: 0, container: "",
        privateKeyAvailable: false, sha256: "", exactDuplicateCount: 1,
        containerCertificateCount: 1, metadataConflict: false
    })

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Certificate")
                description: qsTr("CryptoPro CSP · read-only")
            }

            DetailItem {
                label: qsTr("Subject")
                value: certificate.subject.length > 0 ? certificate.subject : "—"
            }
            DetailItem {
                label: qsTr("Issuer")
                value: certificate.issuer.length > 0 ? certificate.issuer : "—"
            }
            DetailItem {
                label: qsTr("Serial number")
                value: certificate.serial.length > 0 ? certificate.serial : "—"
            }
            DetailItem {
                label: qsTr("Valid from")
                value: certificate.notBefore.length > 0 ? certificate.notBefore : "—"
            }
            DetailItem {
                label: qsTr("Valid until")
                value: certificate.notAfter.length > 0 ? certificate.notAfter : "—"
            }
            DetailItem {
                label: qsTr("Algorithm")
                value: certificate.algorithm.length > 0 ? certificate.algorithm : "—"
            }
            DetailItem {
                label: qsTr("Provider")
                value: certificate.provider.length > 0 ? certificate.provider : "—"
            }
            DetailItem {
                label: qsTr("Provider type")
                value: certificate.providerType
            }
            DetailItem {
                label: qsTr("Container")
                value: certificate.container.length > 0 ? certificate.container : "—"
            }
            DetailItem {
                label: qsTr("Private key")
                value: certificate.privateKeyAvailable ? qsTr("available") : qsTr("unavailable")
            }

            SectionHeader { text: qsTr("Certificate SHA-256") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WrapAnywhere
                textFormat: Text.PlainText
                text: certificate.sha256
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
            }

            SectionHeader {
                visible: certificate.exactDuplicateCount > 1
                         || certificate.containerCertificateCount > 1
                         || certificate.metadataConflict
                text: qsTr("Consistency")
            }
            Label {
                visible: certificate.exactDuplicateCount > 1
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Exact DER copies in the store: %1")
                      .arg(certificate.exactDuplicateCount)
                color: Theme.secondaryColor
            }
            Label {
                visible: certificate.containerCertificateCount > 1
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Different certificates linked to this container: %1")
                      .arg(certificate.containerCertificateCount)
                color: Theme.secondaryColor
            }
            Label {
                visible: certificate.metadataConflict
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("The same DER certificate has conflicting provider or container metadata")
                color: Theme.errorColor
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("This screen does not change certificates or containers")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
