import QtQuick 2.0
import Sailfish.Silica 1.0

// Удаление объекта с токена по NFC. Схема как у прочих NFC-операций
// (PinChangePage): сначала собираем ВСЕ данные без токена — область удаления
// (для сертификата: только сертификат / сертификат+ключи) и PIN-код, — затем в
// ОДНОМ коротком поднесении выполняем удаление за одну сессию
// (deleteObjects: вход по PIN-коду → C_DestroyObject по CKA_ID → перечитывание).
// По успеху обновляем снимок объектов NFC-токена (updateNfcObjects), чтобы
// список сразу отражал удаление. При ошибке — «Начать заново» (сбор с нуля).
//
// Удаление ключа: область не спрашиваем (удаляем всё по CKA_ID, keysToo=true),
// сразу переходим к вводу PIN-кода.
Page {
    id: page
    objectName: "nfcDeletePage"
    allowedOrientations: Orientation.All

    property var slotId: 0            // слот на момент подключения (для справки)
    property string kind: "certificate"  // "certificate" | "key"
    property string idHex: ""
    property string certName: ""
    property bool hasKey: false      // из снимка: точно есть ключ (если вход был по PIN-коду)
    property bool keysKnown: false   // снимок читался после входа по PIN-коду (наличие ключа честно)

    // Собранные значения.
    property bool keysToo: false
    property string pin: ""

    property bool started: false     // первый показ уже отработал
    property bool attempted: false   // область и PIN собраны → ждём поднесения
    property bool nfcStarted: false  // токен обнаружён, удаление запущено
    property bool nfcDone: false     // операция завершена (показать «убрать токен» + результат)

    property bool resultReady: page.nfcDone

    function objTitle() {
        if (page.kind === "key")
            return page.certName.length > 0 ? page.certName : qsTr("the key")
        return page.certName.length > 0 ? page.certName : qsTr("the certificate")
    }

    // Показывать вариант «сертификат+ключи»: когда ключ точно есть, либо когда
    // наличие ключа неизвестно (подключались без PIN-кода) — при удалении будет
    // вход по PIN-коду, и ключ, если он есть, будет найден и удалён.
    function canDeleteKeys() {
        return page.kind === "certificate" && (page.hasKey || !page.keysKnown)
    }

    // Ввод PIN-кода одним экраном (PinPadPage сам закрывается). По вводу —
    // собрано всё, переходим к поднесению.
    function askPin() {
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            subtitle: qsTr("Delete %1").arg(page.objTitle()),
            acceptText: qsTr("Continue")
        })
        pad.entered.connect(function(v) {
            page.pin = v
            page.attempted = true
            tokenWatcher.refresh()
            page.tryNfc()
        })
    }

    // Область выбрана (сертификат) — дальше PIN-код.
    function chooseScope(withKeys) {
        page.keysToo = withKeys
        page.askPin()
    }

    // NFC: найти появившийся NFC-слот и выполнить удаление (один раз).
    function findNfcToken() {
        var ts = tokenWatcher.tokens
        for (var i = 0; i < ts.length; ++i) {
            if (ts[i].connection === "NFC")
                return ts[i]
        }
        return null
    }
    function tryNfc() {
        if (!page.attempted || page.nfcStarted || tokenSession.busy)
            return
        var tok = page.findNfcToken()
        if (!tok)
            return
        page.nfcStarted = true
        tokenSession.deleteObjects(tok.slotId, page.pin, page.idHex, page.keysToo)
    }

    // Перезапуск после ошибки: сброс и повторный сбор с нуля.
    function retry() {
        page.pin = ""
        page.attempted = false
        page.nfcStarted = false
        page.nfcDone = false
        if (page.kind === "key")
            page.askPin()            // ключ — область не спрашиваем
        // сертификат — снова показываем выбор области (attempted=false вернул экран)
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
    // NFC: удаление завершилось — показать «уберите токен» + результат, обновить
    // снимок объектов (при успехе), чтобы список сразу отражал удаление.
    Connections {
        target: tokenSession
        onChanged: {
            if (page.nfcStarted && !page.nfcDone && !tokenSession.busy
                    && tokenSession.outcome !== 0) {
                page.nfcDone = true
                if (tokenSession.outcome === 1)
                    tokenSession.updateNfcObjects()
            }
        }
    }

    // Старт при первом показе: ключ — сразу PIN-код; сертификат — выбор области
    // (кнопки ниже). Возврат «назад» из ввода PIN-кода до сбора: для ключа
    // (области нет) — отмена; для сертификата — снова экран выбора области.
    onStatusChanged: {
        if (status !== PageStatus.Active)
            return
        if (!page.started) {
            page.started = true
            if (page.kind === "key") {
                page.keysToo = true
                page.askPin()
            }
        } else if (!page.attempted && page.kind === "key") {
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

            PageHeader {
                title: page.kind === "key" ? qsTr("Delete key") : qsTr("Delete certificate")
            }

            // --- Сертификат: выбор области удаления (до сбора PIN-кода) ---
            Label {
                visible: page.kind === "certificate" && !page.attempted
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: page.certName.length > 0
                      ? qsTr("Delete “%1” — what should be removed?").arg(page.certName)
                      : qsTr("What should be removed?")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Button {
                visible: page.kind === "certificate" && !page.attempted
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Only the certificate")
                onClicked: page.chooseScope(false)
            }

            Button {
                visible: page.kind === "certificate" && !page.attempted && page.canDeleteKeys()
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Certificate and its keys")
                onClicked: page.chooseScope(true)
            }

            Label {
                visible: page.kind === "certificate" && !page.attempted && page.canDeleteKeys()
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: page.keysKnown
                      ? qsTr("Deleting the keys is irreversible — the private key cannot be recovered.")
                      : qsTr("If the certificate has a private key, entering the PIN will reveal and remove it too.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            // --- NFC: иллюстрация поднесения (после сбора всех данных) ---
            NfcHoldAnimation {
                width: parent.width
                visible: page.attempted
                animState: page.nfcDone ? "removing"
                           : (page.nfcStarted ? "connected" : "searching")
            }

            // --- NFC: поднести токен (пока операция не завершена) ---
            Label {
                visible: page.attempted && !page.nfcDone
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
                visible: page.nfcDone
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("You can remove the token now.")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
            }

            // Индикатор занятости (пока операция идёт).
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: page.attempted && !page.nfcDone
                visible: page.attempted && !page.nfcDone
                size: BusyIndicatorSize.Large
            }

            // Результат.
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
                text: qsTr("Start over")
                onClicked: page.retry()
            }
        }

        VerticalScrollDecorator {}
    }
}
