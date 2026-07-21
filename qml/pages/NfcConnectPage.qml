import QtQuick 2.0
import Sailfish.Silica 1.0

// Мастер подключения по NFC (у NFC своя парадигма — токен держат недолго):
//   шаг 1 — взять токен в руки;
//   шаг 2 — ввод PIN (внешний PinPadPage);
//   шаг 3 — поднести токен к задней крышке (иллюстрация + прогресс), при
//           появлении NFC-слота выполняется операция;
//   шаг 4 — убрать токен, результат.
// operation: "connect" (вход + чтение), "generate", "import". PIN по NFC НЕ
// запоминается — вводится в мастере на каждое подключение.
Page {
    id: page
    objectName: "nfcConnectPage"
    allowedOrientations: Orientation.All

    property string operation: "connect"
    property string algorithm: ""
    property string label: ""
    property string filePath: ""

    property int step: 1
    property string pin: ""
    property bool started: false
    property var lastSlot: 0

    function opTitle() {
        if (page.operation === "generate")
            return qsTr("Generate a key pair over NFC")
        if (page.operation === "import")
            return qsTr("Import a certificate over NFC")
        return qsTr("Connect over NFC")
    }

    function findNfcSlot() {
        var ts = tokenWatcher.tokens
        for (var i = 0; i < ts.length; ++i) {
            if (ts[i].connection === "NFC")
                return ts[i].slotId
        }
        return -1
    }

    function tryRun() {
        if (page.step !== 3 || page.started || tokenSession.busy)
            return
        var slot = page.findNfcSlot()
        if (slot < 0)
            return
        page.started = true
        page.lastSlot = slot
        if (page.operation === "generate")
            tokenSession.generateKeyPair(slot, page.pin, page.algorithm, page.label)
        else if (page.operation === "import")
            tokenSession.importCertificate(slot, page.pin, page.filePath, page.label)
        else
            tokenSession.nfcRead(slot, page.pin)
    }

    function enterPin() {
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            subtitle: page.opTitle(),
            acceptText: qsTr("Continue")
        })
        pad.entered.connect(function(entered) {
            page.pin = entered
            page.step = 3
            tokenWatcher.refresh()
            page.tryRun()
        })
    }

    onStepChanged: if (page.step === 3) page.tryRun()

    // Появился NFC-токен — пытаемся выполнить операцию.
    Connections {
        target: tokenWatcher
        onTokensChanged: page.tryRun()
    }
    // Операция завершилась — переходим к «уберите токен».
    Connections {
        target: tokenSession
        onChanged: {
            if (page.step === 3 && page.started && !tokenSession.busy && tokenSession.outcome !== 0)
                page.step = 4
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader { title: page.opTitle() }

            // --- Шаг 1: взять токен ---
            Column {
                visible: page.step === 1
                width: parent.width
                spacing: Theme.paddingLarge

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Take the Rutoken NFC token in your hand. You will hold it to the back of the phone in a moment.")
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Enter PIN")
                    onClicked: page.enterPin()
                }
            }

            // --- Шаг 3: поднести токен + прогресс ---
            Column {
                visible: page.step === 3
                width: parent.width
                spacing: Theme.paddingLarge

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Hold the token to the back cover and keep it there until the operation finishes.")
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                }

                NfcHoldAnimation {
                    width: parent.width
                    visible: page.step === 3
                }

                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: page.step === 3
                    visible: page.step === 3
                    size: BusyIndicatorSize.Medium
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: page.started ? qsTr("Token detected — working…")
                                       : qsTr("Waiting for the token…")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeMedium
                }
            }

            // --- Шаг 4: убрать токен + результат ---
            Column {
                visible: page.step === 4
                width: parent.width
                spacing: Theme.paddingLarge

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("You can remove the token now.")
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: tokenSession.result
                    color: tokenSession.outcome === 1 ? "#4caf50" : "#f44336"
                    font.pixelSize: Theme.fontSizeMedium
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Done")
                    onClicked: {
                        if (page.operation === "connect" && tokenSession.outcome === 1)
                            pageStack.replace(Qt.resolvedUrl("ObjectsPage.qml"), {
                                slotId: page.lastSlot,
                                connection: "NFC"
                            })
                        else
                            pageStack.pop()
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
