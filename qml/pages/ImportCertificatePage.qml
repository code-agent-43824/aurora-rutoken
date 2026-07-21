import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "importCertificatePage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string connection: "USB"   // "USB" — по кэшу PIN; "NFC" — через мастер
    // Показывать результат только после попытки на этом экране (outcome общий).
    property bool attempted: false

    function doImport() {
        if (tokenSession.busy || pathField.text.length === 0)
            return
        Qt.inputMethod.commit()
        if (page.connection === "NFC") {
            // По NFC — через мастер (взять токен → PIN → поднести → импорт).
            pageStack.push(Qt.resolvedUrl("NfcConnectPage.qml"), {
                operation: "import",
                filePath: pathField.text,
                label: labelField.text
            })
            return
        }
        if (!tokenSession.loggedIn)
            return
        page.attempted = true
        tokenSession.importCertificateCached(page.slotId, pathField.text, labelField.text)
    }

    // Вход по PIN (цифровой экран); используется запомненный PIN для импорта.
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

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Import certificate")
                description: qsTr("From a file to the token")
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Choose a file")
                enabled: !tokenSession.busy
                onClicked: {
                    // Экран выбора изолирует зависимость Sailfish.Pickers.
                    var picker = pageStack.push(Qt.resolvedUrl("CertFilePickerPage.qml"))
                    picker.picked.connect(function(path) {
                        if (path && path.length > 0)
                            pathField.text = path
                    })
                }
            }

            TextField {
                id: pathField
                width: parent.width
                label: qsTr("Certificate file (PEM or DER)")
                placeholderText: qsTr("Pick a file or type a path")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: labelField.focus = true
            }

            TextField {
                id: labelField
                width: parent.width
                label: qsTr("Certificate label (optional)")
                placeholderText: qsTr("Taken from Common Name if empty")
                inputMethodHints: Qt.ImhNoPredictiveText
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.doImport()
            }

            // USB: требуется вход по PIN. Если не вошли — открыть цифровой экран PIN;
            // после входа PIN запоминается и импорт идёт без повторного ввода.
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
                text: tokenSession.busy ? qsTr("Importing…") : qsTr("Import")
                enabled: !tokenSession.busy && pathField.text.length > 0
                         && (page.connection === "NFC" || tokenSession.loggedIn)
                onClicked: page.doImport()
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: tokenSession.busy
                visible: tokenSession.busy
                size: BusyIndicatorSize.Medium
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                visible: page.attempted && !tokenSession.busy && tokenSession.outcome !== 0
                text: tokenSession.result
                color: tokenSession.outcome === 1 ? "#4caf50" : "#f44336"
                font.pixelSize: Theme.fontSizeMedium
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                visible: page.attempted && !tokenSession.busy && tokenSession.outcome === 1
                text: qsTr("Swipe back to see the certificate in the list.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Only the certificate (public) is imported — never a private key.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
