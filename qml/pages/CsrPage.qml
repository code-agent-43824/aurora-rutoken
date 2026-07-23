import QtQuick 2.0
import Sailfish.Silica 1.0

// Формирование запроса на сертификат (PKCS#10) для ключевой пары на токене
// (по CKA_ID). Заполняем Subject (DN), подписываем закрытым ключом на токене,
// получаем PEM — его видно на экране (выделяемый) и можно сохранить в файл .csr.
//
// USB — вход по PIN (кэш). NFC — сбор DN здесь, затем мастер поднесения
// (NfcConnectPage, operation="csr"): ввод PIN-кода и одно поднесение выполняют
// подпись; по возвращении PEM показывается тут же (из lastCsr). Результат (PEM)
// показывается на этом экране — это итог операции, к списку объектов не уходим.
Page {
    id: page
    objectName: "csrPage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string idHex: ""
    property string keyName: ""       // подсказка для CN и имени файла
    property string connection: "USB"
    property bool attempted: false

    property bool hasCsr: tokenSession.lastCsr.length > 0
                          && page.attempted && !tokenSession.busy && tokenSession.outcome === 1

    function doCreate() {
        if (tokenSession.busy || cnField.text.length === 0)
            return
        Qt.inputMethod.commit()
        if (page.connection === "NFC") {
            // По NFC — через мастер (взять токен → PIN-код → поднести → подпись).
            // По возвращении CsrPage покажет PEM из lastCsr.
            page.attempted = true
            pageStack.push(Qt.resolvedUrl("NfcConnectPage.qml"), {
                operation: "csr",
                idHex: page.idHex,
                csrDn: {
                    cn: cnField.text, o: oField.text, ou: ouField.text,
                    c: cField.text, l: lField.text, st: stField.text, email: eField.text
                }
            })
            return
        }
        if (!tokenSession.loggedIn)
            return
        page.attempted = true
        tokenSession.createCsrCached(page.slotId, page.idHex,
                                     cnField.text, oField.text, ouField.text,
                                     cField.text, lField.text, stField.text, eField.text)
    }

    // Вход по PIN (цифровой экран); далее CSR идёт по запомненному PIN.
    function openPinPad() {
        if (tokenSession.busy)
            return
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            acceptText: qsTr("Log in")
        })
        pad.entered.connect(function(pin) {
            tokenSession.login(page.slotId, pin)
        })
    }

    function saveCsr() {
        var base = cnField.text.length > 0 ? cnField.text : "request"
        saveResult.text = tokenSession.saveCsrToFile(tokenSession.lastCsr, "", base)
        saveResult.visible = true
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Certificate request")
                description: qsTr("PKCS#10, signed on the token")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                visible: page.keyName.length > 0
                text: qsTr("For the key pair: %1").arg(page.keyName)
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
            }

            TextField {
                id: cnField
                width: parent.width
                label: qsTr("Common Name (CN) — required")
                placeholderText: qsTr("For example, Ivan Ivanov")
                text: page.keyName
                inputMethodHints: Qt.ImhNoPredictiveText
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: oField.focus = true
            }
            TextField {
                id: oField
                width: parent.width
                label: qsTr("Organization (O)")
                inputMethodHints: Qt.ImhNoPredictiveText
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: ouField.focus = true
            }
            TextField {
                id: ouField
                width: parent.width
                label: qsTr("Organizational Unit (OU)")
                inputMethodHints: Qt.ImhNoPredictiveText
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: cField.focus = true
            }
            TextField {
                id: cField
                width: parent.width
                label: qsTr("Country (C) — two letters")
                placeholderText: qsTr("For example, RU")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: lField.focus = true
            }
            TextField {
                id: lField
                width: parent.width
                label: qsTr("Locality (L)")
                inputMethodHints: Qt.ImhNoPredictiveText
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: stField.focus = true
            }
            TextField {
                id: stField
                width: parent.width
                label: qsTr("State / Province (ST)")
                inputMethodHints: Qt.ImhNoPredictiveText
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: eField.focus = true
            }
            TextField {
                id: eField
                width: parent.width
                label: qsTr("Email")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhEmailCharactersOnly
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.doCreate()
            }

            // USB: требуется вход по PIN.
            Button {
                visible: page.connection !== "NFC" && !tokenSession.loggedIn
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Checking…") : qsTr("Enter PIN")
                enabled: !tokenSession.busy
                onClicked: page.openPinPad()
            }
            Label {
                visible: page.connection !== "NFC" && tokenSession.loggedIn
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("PIN is remembered")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
            // NFC: PIN вводится в мастере при поднесении токена.
            Label {
                visible: page.connection === "NFC"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Over NFC you will enter the PIN and hold the token in the next step.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Creating…") : qsTr("Create request")
                enabled: !tokenSession.busy && cnField.text.length > 0
                         && (page.connection === "NFC" || tokenSession.loggedIn)
                onClicked: page.doCreate()
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: tokenSession.busy
                visible: tokenSession.busy
                size: BusyIndicatorSize.Medium
            }

            // Результат операции (ошибка или подтверждение до показа PEM).
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                visible: page.attempted && !tokenSession.busy && tokenSession.outcome !== 0
                text: tokenSession.result
                color: tokenSession.outcome === 1 ? "#4caf50" : "#f44336"
                font.pixelSize: Theme.fontSizeSmall
            }

            // PEM запроса — выделяемый, для копирования; плюс сохранение в файл.
            TextArea {
                id: pemArea
                width: parent.width
                visible: page.hasCsr
                readOnly: true
                label: qsTr("Certificate request (PEM)")
                text: tokenSession.lastCsr
                font.pixelSize: Theme.fontSizeExtraSmall
                font.family: "monospace"
            }

            Button {
                visible: page.hasCsr
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Save to file (.csr)")
                onClicked: page.saveCsr()
            }

            Label {
                id: saveResult
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                visible: false
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("The request is signed by the private key on the token; the private key never leaves it.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
