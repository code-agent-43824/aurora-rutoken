import QtQuick 2.0
import Sailfish.Silica 1.0

// Запрос на сертификат (PKCS#10) для контейнера КриптоПро (v1.3).
// Запрос кодирует и подписывает сам провайдер, поэтому приложение не разбирает
// раскладку ключа и не переставляет байты подписи ГОСТ.
Page {
    id: page
    objectName: "cryptoProCsrPage"
    allowedOrientations: Orientation.All

    property string container: ""        // полный путь контейнера (FQCN)
    property int providerType: 80
    property string deviceLabel: ""
    // "USB" — операция идёт прямо отсюда; "NFC" — через мастер поднесения.
    property string connection: "USB"

    property bool attempted: false

    function start() {
        if (cryptoProSession.createBusy)
            return
        if (cnField.text.trim().length === 0) {
            cnField.errorHighlight = true
            return
        }
        var subject = {
            cn: cnField.text.trim(),
            o: oField.text.trim(),
            ou: ouField.text.trim(),
            c: cField.text.trim(),
            l: lField.text.trim(),
            st: stField.text.trim(),
            email: emailField.text.trim()
        }
        if (page.connection === "NFC") {
            // По NFC — через мастер (взять устройство → PIN → поднести →
            // формирование запроса). Готовый PEM появится на этой же форме:
            // запрос хранится в сессии, а объекты устройства он не меняет.
            page.attempted = true
            pageStack.push(Qt.resolvedUrl("NfcConnectPage.qml"), {
                operation: "cpcsr",
                cpContainer: page.container,
                cpProviderType: page.providerType,
                cpSubject: subject
            })
            return
        }
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            subtitle: page.deviceLabel.length > 0 ? page.deviceLabel : qsTr("Rutoken"),
            acceptText: qsTr("Create request")
        })
        pad.entered.connect(function(pin) {
            page.attempted = true
            cryptoProSession.createCertificateRequest(page.container, page.providerType,
                                                      pin, subject)
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                visible: cryptoProSession.lastRequest.length > 0
                text: qsTr("Save request to file")
                onClicked: cryptoProSession.saveRequestToFile(
                               cnField.text.trim().length > 0 ? cnField.text.trim() : "request")
            }
        }

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Certificate request")
                description: qsTr("CryptoPro CSP")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: qsTr("container: %1").arg(page.container)
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            TextField {
                id: cnField
                width: parent.width
                label: qsTr("Common Name (required)")
                placeholderText: qsTr("Common Name (required)")
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: oField.focus = true
                onTextChanged: errorHighlight = false
            }
            TextField {
                id: oField
                width: parent.width
                label: qsTr("Organization")
                placeholderText: qsTr("Organization")
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: ouField.focus = true
            }
            TextField {
                id: ouField
                width: parent.width
                label: qsTr("Organizational unit")
                placeholderText: qsTr("Organizational unit")
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: cField.focus = true
            }
            TextField {
                id: cField
                width: parent.width
                label: qsTr("Country (2 letters)")
                placeholderText: qsTr("Country (2 letters)")
                inputMethodHints: Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: lField.focus = true
            }
            TextField {
                id: lField
                width: parent.width
                label: qsTr("Locality")
                placeholderText: qsTr("Locality")
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: stField.focus = true
            }
            TextField {
                id: stField
                width: parent.width
                label: qsTr("State or region")
                placeholderText: qsTr("State or region")
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: emailField.focus = true
            }
            TextField {
                id: emailField
                width: parent.width
                label: qsTr("Email")
                placeholderText: qsTr("Email")
                inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: cryptoProSession.createBusy ? qsTr("Creating…") : qsTr("Create request")
                enabled: !cryptoProSession.createBusy
                onClicked: page.start()
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: cryptoProSession.createBusy
                visible: cryptoProSession.createBusy
                size: BusyIndicatorSize.Medium
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                visible: page.attempted && !cryptoProSession.createBusy
                         && cryptoProSession.createOutcome !== 0
                text: cryptoProSession.createResult
                color: cryptoProSession.createOutcome === 1 ? "#4caf50" : "#f44336"
                font.pixelSize: Theme.fontSizeSmall
            }

            // Готовый PEM: его можно выделить и скопировать либо сохранить в файл
            // пунктом меню-шторки.
            TextArea {
                visible: cryptoProSession.lastRequest.length > 0
                width: parent.width
                readOnly: true
                font.pixelSize: Theme.fontSizeExtraSmall
                text: cryptoProSession.lastRequest
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: cryptoProSession.lastRequest.length > 0
                wrapMode: Text.Wrap
                text: qsTr("Pull down to save the request as a .csr file in Downloads.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
