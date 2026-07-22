import QtQuick 2.0
import Sailfish.Silica 1.0

// Управление PIN. mode: "user" | "so" | "unblock". connection: "USB" | "NFC".
// Сбор PIN одинаков для обеих схем — прямая цепочка отдельных экранов ввода
// (PinPadPage, autoPop=false), БЕЗ возврата к этому экрану между шагами и без
// списка введённых значений: старый PIN → новый → повтор нового (unblock — один
// экран). Первый шаг — push поверх этого экрана, следующие — pageStack.replace,
// поэтому над контроллером всегда ровно один экран ввода, а возврат за
// результатом — простой pageStack.pop(). Жест «назад» с экрана ввода отменяет
// поток (см. onStatusChanged).
//
// Отличается только ВЫПОЛНЕНИЕ:
//   USB — операция запускается сразу (токен всегда на связи);
//   NFC — сначала собираем ВСЕ PIN (без токена), затем в ОДНОМ коротком
//         поднесении выполняем операцию за раз (детект слота как в NfcConnectPage);
//         результат + «убрать токен», при ошибке — «Начать заново» (сбор с нуля).
Page {
    id: page
    objectName: "pinChangePage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string mode: "user"
    property string connection: "USB"

    // Собранные значения.
    property string oldPin: ""
    property string newPin: ""
    property string confirmPin: ""

    property bool started: false    // первый показ уже открыл первый экран
    property bool attempted: false  // все PIN собраны → выполнение (USB) / поднесение (NFC)
    // Только для NFC:
    property bool nfcStarted: false // токен обнаружён, операция запущена
    property bool nfcDone: false    // операция завершена (показать «убрать токен» + результат)

    // Результат готов к показу (USB — по завершении; NFC — после nfcDone).
    property bool resultReady: (page.connection === "NFC" && page.nfcDone)
            || (page.connection !== "NFC" && page.attempted && !tokenSession.busy
                && tokenSession.outcome !== 0)

    function titleText() {
        if (mode === "so") return qsTr("Change admin PIN")
        if (mode === "unblock") return qsTr("Unblock user PIN")
        return qsTr("Change user PIN")
    }
    function oldHeading() {
        if (mode === "so") return qsTr("Current admin PIN")
        if (mode === "unblock") return qsTr("Administrator (SO) PIN")
        return qsTr("Current user PIN")
    }
    function newHeading() {
        if (mode === "so") return qsTr("New admin PIN")
        return qsTr("New user PIN")
    }

    // Открыть очередной экран ввода. useReplace=false — первый шаг (push поверх
    // этого экрана); true — следующий шаг (replace: заменяет предыдущий экран
    // ввода, этот контроллер между шагами не показывается). PinPadPage с
    // autoPop=false сам не закрывается — навигацию ведёт этот контроллер.
    function openPad(useReplace, heading, subtitle, onEntered) {
        var props = {
            heading: heading,
            subtitle: subtitle,
            acceptText: qsTr("OK"),
            autoPop: false
        }
        var pad = useReplace
                ? pageStack.replace(Qt.resolvedUrl("PinPadPage.qml"), props)
                : pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), props)
        pad.entered.connect(onEntered)
        return pad
    }

    function askOld() {
        page.openPad(false, page.oldHeading(), "", function(v) { page.onOld(v) })
    }
    function askNew(subtitle) {
        page.openPad(true, page.newHeading(), subtitle, function(v) { page.onNew(v) })
    }
    function askConfirm() {
        page.openPad(true, qsTr("Confirm new PIN"), "", function(v) { page.onConfirm(v) })
    }

    function onOld(v) {
        page.oldPin = v
        if (page.mode === "unblock")
            page.runOp()                // разблокировка — только PIN администратора
        else
            page.askNew("")             // дальше — новый PIN
    }
    function onNew(v) {
        page.newPin = v
        page.askConfirm()
    }
    function onConfirm(v) {
        page.confirmPin = v
        if (page.newPin === page.confirmPin) {
            page.runOp()
        } else {
            // Новые PIN не совпали — просим новый и повтор заново с подсказкой.
            page.newPin = ""
            page.confirmPin = ""
            page.askNew(qsTr("The new PINs do not match"))
        }
    }

    // Все PIN собраны — закрываем экран ввода (над нами он один → простой pop).
    // USB: сразу выполняем. NFC: ждём поднесения (иллюстрация), затем выполняем.
    function runOp() {
        page.attempted = true
        pageStack.pop()
        if (page.connection === "NFC") {
            tokenWatcher.refresh()
            page.tryNfc()
        } else {
            page.exec(page.slotId)
        }
    }

    // Запуск самой операции на заданном слоте (одна короткая сессия внутри).
    function exec(slot) {
        if (page.mode === "so")
            tokenSession.changeSoPin(slot, page.oldPin, page.newPin)
        else if (page.mode === "unblock")
            tokenSession.unblockUserPin(slot, page.oldPin)
        else
            tokenSession.changeUserPin(slot, page.oldPin, page.newPin)
    }

    // NFC: найти появившийся NFC-слот и выполнить операцию (один раз).
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
        page.exec(tok.slotId)
    }

    // Перезапуск: сброс и повторный сбор PIN с нуля (USB — «Ещё раз», NFC —
    // «Начать заново» после ошибки).
    function retry() {
        page.oldPin = ""
        page.newPin = ""
        page.confirmPin = ""
        page.attempted = false
        page.nfcStarted = false
        page.nfcDone = false
        page.askOld()
    }

    function feedback(ev) {
        if (feedbackLoader.status === Loader.Ready && feedbackLoader.item)
            feedbackLoader.item.play(ev)
    }
    onNfcStartedChanged: if (page.nfcStarted) page.feedback("positive") // токен обнаружен
    onNfcDoneChanged: if (page.nfcDone) page.feedback("general")        // рассоединение

    // Изолированная зависимость системных звуков (может отсутствовать — тогда тихо).
    Loader {
        id: feedbackLoader
        source: Qt.resolvedUrl("Feedback.qml")
    }

    // NFC: появился слот — пробуем выполнить.
    Connections {
        target: tokenWatcher
        onTokensChanged: page.tryNfc()
    }
    // NFC: операция завершилась — показать «уберите токен» + результат.
    Connections {
        target: tokenSession
        onChanged: {
            if (page.connection === "NFC" && page.nfcStarted && !page.nfcDone
                    && !tokenSession.busy && tokenSession.outcome !== 0)
                page.nfcDone = true
        }
    }

    // Старт цепочки при первом показе. Если экран снова стал активным ДО сбора
    // всех PIN — значит пользователь вышел «назад» из ввода: отменяем всё.
    onStatusChanged: {
        if (status !== PageStatus.Active)
            return
        if (!page.started) {
            page.started = true
            page.askOld()
        } else if (!page.attempted) {
            pageStack.pop()
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader { title: page.titleText() }

            // --- NFC: иллюстрация поднесения (после сбора всех PIN) ---
            NfcHoldAnimation {
                width: parent.width
                visible: page.connection === "NFC" && page.attempted
                animState: page.nfcDone ? "removing"
                           : (page.nfcStarted ? "connected" : "searching")
            }

            // --- NFC: поднести токен (пока операция не завершена) ---
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

            // --- NFC: убрать токен (после завершения) ---
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

            // Индикатор занятости (USB — сразу; NFC — пока операция идёт).
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: tokenSession.busy
                         || (page.connection === "NFC" && page.attempted && !page.nfcDone)
                visible: tokenSession.busy
                         || (page.connection === "NFC" && page.attempted && !page.nfcDone)
                size: BusyIndicatorSize.Large
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
                font.pixelSize: Theme.fontSizeLarge
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.resultReady && tokenSession.outcome === 1
                text: qsTr("Done")
                onClicked: pageStack.pop()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.resultReady && tokenSession.outcome === -1
                text: page.connection === "NFC" ? qsTr("Start over") : qsTr("Try again")
                onClicked: page.retry()
            }
        }

        VerticalScrollDecorator {}
    }
}
