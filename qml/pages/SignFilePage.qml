import QtQuick 2.0
import Sailfish.Silica 1.0

// CMS/PKCS#7-подпись файла выбранным сертификатом Рутокена.
// USB использует запомненный PIN, NFC передаёт все параметры в существующий
// мастер одного поднесения. Проверка готовой подписи намеренно не входит в v1.1.
Page {
    id: page
    objectName: "signFilePage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string idHex: ""
    property string certificateDerB64: ""
    property string certificateName: ""
    property string connection: "USB"
    property bool attempted: false

    function sourceFileName(path) {
        var normalized = path ? path.replace(/\\/g, "/") : ""
        var parts = normalized.split("/")
        return parts.length > 0 ? parts[parts.length - 1] : ""
    }

    function chooseFile() {
        var picker = pageStack.push(Qt.resolvedUrl("SignDataFilePickerPage.qml"))
        picker.picked.connect(function(path) {
            if (!path || path.length === 0)
                return
            sourcePath.text = path
            if (outputName.text.length === 0)
                outputName.text = page.sourceFileName(path)
        })
    }

    function openPinPad() {
        if (tokenSession.busy)
            return
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            subtitle: page.certificateName,
            acceptText: qsTr("Log in")
        })
        pad.entered.connect(function(pin) {
            tokenSession.login(page.slotId, pin)
        })
    }

    function doSign() {
        if (tokenSession.busy || sourcePath.text.length === 0
                || outputName.text.trim().length === 0)
            return
        Qt.inputMethod.commit()
        page.attempted = true
        var detached = formatCombo.currentIndex === 0
        if (page.connection === "NFC") {
            pageStack.push(Qt.resolvedUrl("NfcConnectPage.qml"), {
                operation: "cms",
                idHex: page.idHex,
                cmsCertificateDerB64: page.certificateDerB64,
                cmsSourcePath: sourcePath.text,
                cmsDetached: detached,
                cmsOutputDir: outputDir.text,
                cmsOutputName: outputName.text
            })
        } else {
            tokenSession.signCmsCached(page.slotId, page.idHex,
                                       page.certificateDerB64, sourcePath.text,
                                       detached, outputDir.text, outputName.text)
        }
    }

    Component.onCompleted: {
        if (outputDir.text.length === 0)
            outputDir.text = tokenSession.defaultExportDir()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("Sign a file")
                description: qsTr("CMS/PKCS#7 on the Rutoken")
            }

            DetailItem {
                label: qsTr("Certificate")
                value: page.certificateName.length > 0 ? page.certificateName : "—"
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Choose a file")
                enabled: !tokenSession.busy
                onClicked: page.chooseFile()
            }

            TextField {
                id: sourcePath
                width: parent.width
                label: qsTr("Source file")
                placeholderText: qsTr("Pick a file or type a path")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: outputName.focus = true
            }

            ComboBox {
                id: formatCombo
                width: parent.width
                label: qsTr("Signature format")
                enabled: !tokenSession.busy
                menu: ContextMenu {
                    MenuItem { text: qsTr("Detached CMS (.p7s)") }
                    MenuItem { text: qsTr("Attached CMS (.p7m)") }
                }
            }

            TextField {
                id: outputName
                width: parent.width
                label: qsTr("Result file name")
                placeholderText: qsTr("Extension is added automatically")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: outputDir.focus = true
            }

            TextField {
                id: outputDir
                width: parent.width
                label: qsTr("Save to folder")
                placeholderText: tokenSession.defaultExportDir()
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.doSign()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: formatCombo.currentIndex === 0
                      ? qsTr("Detached: the source file is not included in the CMS.")
                      : qsTr("Attached: the source file is included in the CMS.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Button {
                visible: page.connection !== "NFC" && !tokenSession.loggedIn
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Checking…") : qsTr("Enter PIN")
                enabled: !tokenSession.busy
                onClicked: page.openPinPad()
            }

            Label {
                visible: page.connection === "NFC"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Over NFC you will enter the PIN and hold the device in the next step.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Signing…") : qsTr("Sign")
                enabled: !tokenSession.busy && sourcePath.text.length > 0
                         && outputName.text.trim().length > 0
                         && (page.connection === "NFC" || tokenSession.loggedIn)
                onClicked: page.doSign()
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
                visible: page.attempted && !tokenSession.busy
                         && tokenSession.outcome !== 0
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: tokenSession.result
                color: tokenSession.outcome === 1 ? "#4caf50" : "#f44336"
                font.pixelSize: Theme.fontSizeSmall
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("An existing result file is never overwritten. Signature verification will be added later.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
