import QtQuick 2.0
import Sailfish.Silica 1.0

// Смена метки токена (vendor C_EX_SetTokenName) — требует PIN пользователя.
// connection: "USB" | "NFC". Сбор одинаков (поле метки + PIN на форме); отличие —
// выполнение: USB запускает операцию сразу; NFC собирает данные, затем в ОДНОМ
// коротком поднесении выполняет за сессию (доп. экран прикладывания), при ошибке —
// «Начать заново».
Page {
    id: page
    objectName: "tokenLabelPage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string currentLabel: ""
    property string connection: "USB"
    property string userPin: ""
    property bool attempted: false
    property bool refreshed: false
    // Только для NFC:
    property bool nfcStarted: false
    property bool nfcDone: false

    property bool resultReady: (page.connection === "NFC" && page.nfcDone)
            || (page.connection !== "NFC" && page.attempted && !tokenSession.busy
                && tokenSession.outcome !== 0)

    Connections {
        target: tokenSession
        onChanged: {
            // USB: после успешной смены перечитываем список токенов (метка в
            // сигнатуре TokenWatcher) — новая метка появляется в деталях и списке.
            if (page.connection !== "NFC" && page.attempted && !page.refreshed
                    && !tokenSession.busy && tokenSession.outcome === 1) {
                page.refreshed = true
                page.currentLabel = labelField.text
                tokenWatcher.refresh()
            }
            // NFC: операция завершилась → «уберите токен» + результат; при успехе
            // обновляем метку в снимке (токен уже убран, живого чтения нет).
            if (page.connection === "NFC" && page.nfcStarted && !page.nfcDone
                    && !tokenSession.busy && tokenSession.outcome !== 0) {
                page.nfcDone = true
                if (tokenSession.outcome === 1)
                    tokenSession.setNfcLabel(labelField.text)
            }
        }
    }

    function openPad() {
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            acceptText: qsTr("OK")
        })
        pad.entered.connect(function(value) { page.userPin = value })
    }

    function doApply() {
        if (tokenSession.busy || labelField.text.length === 0 || page.userPin.length === 0)
            return
        Qt.inputMethod.commit()
        page.attempted = true
        if (page.connection === "NFC") {
            tokenWatcher.refresh()
            page.tryNfc()
        } else {
            tokenSession.changeTokenLabel(page.slotId, page.userPin, labelField.text)
        }
    }

    // NFC: выполнить смену метки на появившемся слоте (один раз, одна сессия).
    function findNfcToken() {
        var ts = tokenWatcher.tokens
        for (var i = 0; i < ts.length; ++i) {
            if (ts[i].connection === "NFC")
                return ts[i]
        }
        return null
    }
    function tryNfc() {
        if (page.connection !== "NFC" || !page.attempted || page.nfcStarted || tokenSession.busy)
            return
        var tok = page.findNfcToken()
        if (!tok)
            return
        page.nfcStarted = true
        tokenSession.changeTokenLabel(tok.slotId, page.userPin, labelField.text)
    }

    // NFC «Начать заново»: вернуться к форме (данные остаются — можно поправить).
    function retry() {
        page.attempted = false
        page.nfcStarted = false
        page.nfcDone = false
    }

    function feedback(ev) {
        if (feedbackLoader.status === Loader.Ready && feedbackLoader.item)
            feedbackLoader.item.play(ev)
    }
    onNfcStartedChanged: if (page.nfcStarted) page.feedback("positive")
    onNfcDoneChanged: if (page.nfcDone) page.feedback("general")

    Loader {
        id: feedbackLoader
        source: Qt.resolvedUrl("Feedback.qml")
    }

    Connections {
        target: tokenWatcher
        onTokensChanged: page.tryNfc()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("Change token label") }

            // --- Форма сбора (для USB всегда; для NFC — пока не начали) ---
            TextField {
                id: labelField
                visible: page.connection !== "NFC" || !page.attempted
                width: parent.width
                label: qsTr("Token label")
                placeholderText: qsTr("New token label")
                text: page.currentLabel
                inputMethodHints: Qt.ImhNoPredictiveText
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.doApply()
            }

            Button {
                visible: page.connection !== "NFC" || !page.attempted
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.userPin.length > 0
                      ? qsTr("User PIN") + ": ●●●●"
                      : qsTr("Enter user PIN")
                enabled: !tokenSession.busy
                onClicked: page.openPad()
            }

            Button {
                visible: page.connection !== "NFC" || !page.attempted
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Applying…") : qsTr("Change label")
                enabled: !tokenSession.busy && labelField.text.length > 0 && page.userPin.length > 0
                onClicked: page.doApply()
            }

            // --- NFC: иллюстрация поднесения + подсказки ---
            NfcHoldAnimation {
                width: parent.width
                visible: page.connection === "NFC" && page.attempted
                animState: page.nfcDone ? "removing"
                           : (page.nfcStarted ? "connected" : "searching")
            }

            Label {
                visible: page.connection === "NFC" && page.attempted && !page.nfcDone
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: page.nfcStarted
                      ? qsTr("Keep holding the token — the operation is running.")
                      : qsTr("Hold the token to the back cover and keep it there.")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
            }

            Label {
                visible: page.connection === "NFC" && page.nfcDone
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("You can remove the token now.")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: tokenSession.busy
                         || (page.connection === "NFC" && page.attempted && !page.nfcDone)
                visible: tokenSession.busy
                         || (page.connection === "NFC" && page.attempted && !page.nfcDone)
                size: BusyIndicatorSize.Medium
            }

            // Результат (обе схемы).
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                visible: page.resultReady
                text: tokenSession.result
                color: tokenSession.outcome === 1 ? "#4caf50" : "#f44336"
                font.pixelSize: Theme.fontSizeMedium
            }

            // NFC: кнопки после завершения.
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.connection === "NFC" && page.nfcDone && tokenSession.outcome === 1
                text: qsTr("Done")
                onClicked: pageStack.pop()
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.connection === "NFC" && page.nfcDone && tokenSession.outcome === -1
                text: qsTr("Start over")
                onClicked: page.retry()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                // USB — как раньше (всегда); NFC — только пока собираем данные.
                visible: page.connection !== "NFC" || !page.attempted
                text: qsTr("Changing the label requires the user PIN and does not erase the token.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
