import QtQuick 2.0
import Sailfish.Silica 1.0

// Мастер подключения по NFC (у NFC своя парадигма — токен держат недолго):
//   шаг 1 — взять токен в руки;
//   шаг 2 — ввод PIN (внешний PinPadPage);
//   шаг 3 — поднести токен к задней крышке (иллюстрация + прогресс), при
//           появлении NFC-слота выполняется операция;
//   шаг 4 — убрать токен, результат.
// operation: "connect" (вход + чтение), "generate", "import". PIN по NFC НЕ
// запоминается. После connect токен «логически подключается» (снимок объектов
// сохраняется в TokenSession) — к нему можно вернуться без повторного поднесения.
Page {
    id: page
    objectName: "nfcConnectPage"
    allowedOrientations: Orientation.All

    property string operation: "connect"
    property string algorithm: ""
    property string label: ""
    property string filePath: ""
    // Для operation="csr": ключевая пара по CKA_ID и поля Subject (DN).
    property string idHex: ""
    property var csrDn: null

    property int step: 1
    property string pin: ""
    property bool noPin: false      // подключение без входа (только публичные сертификаты)
    property bool started: false
    property var lastToken: null

    // Успешное завершение записи по NFC (генерация/импорт). Форма-инициатор
    // (GenerateKeyPage/ImportCertificatePage) по нему возвращается к списку объектов.
    signal finishedOk()

    function opTitle() {
        if (page.operation === "generate")
            return qsTr("Generate a key pair over NFC")
        if (page.operation === "import")
            return qsTr("Import a certificate over NFC")
        if (page.operation === "csr")
            return qsTr("Certificate request over NFC")
        return qsTr("Connect over NFC")
    }

    function findNfcToken() {
        var ts = tokenWatcher.tokens
        for (var i = 0; i < ts.length; ++i) {
            if (ts[i].connection === "NFC")
                return ts[i]
        }
        return null
    }

    function tryRun() {
        if (page.step !== 3 || page.started || tokenSession.busy)
            return
        var tok = page.findNfcToken()
        if (!tok)
            return
        page.started = true
        page.lastToken = tok
        if (page.operation === "generate")
            tokenSession.generateKeyPair(tok.slotId, page.pin, page.algorithm, page.label)
        else if (page.operation === "import")
            tokenSession.importCertificate(tok.slotId, page.pin, page.filePath, page.label)
        else if (page.operation === "csr")
            tokenSession.createCsr(tok.slotId, page.pin, page.idHex,
                                   page.csrDn.cn, page.csrDn.o, page.csrDn.ou, page.csrDn.c,
                                   page.csrDn.l, page.csrDn.st, page.csrDn.email)
        else if (page.noPin)
            tokenSession.preview(tok.slotId)   // без входа — только публичные сертификаты
        else
            tokenSession.nfcRead(tok.slotId, page.pin)
    }

    function enterPin() {
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            subtitle: page.opTitle(),
            acceptText: qsTr("Continue")
        })
        pad.entered.connect(function(entered) {
            page.pin = entered
            page.noPin = false
            page.step = 3
            tokenWatcher.refresh()
            page.tryRun()
        })
    }

    // Повтор после неудачи (например, токен убрали слишком рано): снова ждём
    // поднесения и выполняем ту же операцию с уже введённым PIN-кодом — без
    // повторного ввода PIN и данных.
    function retryNfc() {
        page.started = false
        page.step = 3
        tokenWatcher.refresh()
        page.tryRun()
    }

    // Подключение без PIN-кода: читаем только публичные сертификаты (без входа).
    function continueNoPin() {
        page.pin = ""
        page.noPin = true
        page.step = 3
        tokenWatcher.refresh()
        page.tryRun()
    }

    function feedback(ev) {
        if (feedbackLoader.status === Loader.Ready && feedbackLoader.item)
            feedbackLoader.item.play(ev)
    }

    onStepChanged: {
        if (page.step === 3)
            page.tryRun()
        else if (page.step === 4)
            page.feedback("general")   // звук рассоединения
    }
    onStartedChanged: {
        if (page.started)
            page.feedback("positive")  // звук соединения (токен обнаружен)
    }

    // Изолированная зависимость системных звуков (может отсутствовать — тогда тихо).
    Loader {
        id: feedbackLoader
        source: Qt.resolvedUrl("Feedback.qml")
    }

    // Появился NFC-токен — пытаемся выполнить операцию.
    Connections {
        target: tokenWatcher
        onTokensChanged: page.tryRun()
    }
    // Операция завершилась — переходим к «уберите токен». Для чтения без входа
    // (preview) outcome остаётся 0, поэтому там ориентируемся только на busy.
    Connections {
        target: tokenSession
        onChanged: {
            if (page.step === 3 && page.started && !tokenSession.busy
                    && (tokenSession.outcome !== 0 || page.noPin))
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
                // Подключение без входа — видны только публичные сертификаты.
                Button {
                    visible: page.operation === "connect"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Continue without PIN")
                    onClicked: page.continueNoPin()
                }
            }

            // --- Иллюстрация (шаги 3 и 4), меняется по состоянию ---
            NfcHoldAnimation {
                width: parent.width
                visible: page.step === 3 || page.step === 4
                animState: page.step === 4 ? "removing"
                           : (page.started ? "connected" : "searching")
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
                    text: page.started
                          ? qsTr("Keep holding the token — the operation is running.")
                          : qsTr("Hold the token to the back cover and keep it there.")
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
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
                // Повтор при неудаче (например, токен убрали слишком рано) —
                // без повторного ввода PIN-кода/данных.
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !tokenSession.busy && tokenSession.outcome === -1
                    text: qsTr("Try again")
                    onClicked: page.retryNfc()
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Done")
                    onClicked: {
                        if ((tokenSession.outcome === 1 || page.noPin) && page.operation === "connect") {
                            // Логически подключаем NFC-токен (снимок объектов) и
                            // открываем ЕГО СВОЙСТВА (как у USB). Сертификаты уже
                            // считаны при подключении (по PIN-коду — с ключами,
                            // без PIN-кода — только публичные) — из деталей их видно
                            // без повторного поднесения.
                            tokenSession.commitNfc(page.lastToken)
                            var t = page.lastToken
                            pageStack.replace(Qt.resolvedUrl("TokenPage.qml"), {
                                connection: "NFC",
                                slotId: (t && t.slotId) ? t.slotId : 0,
                                tokenLabel: (t && t.label) ? t.label : "",
                                serial: (t && t.serial) ? t.serial : "",
                                tokenModel: (t && t.model) ? t.model : "",
                                manufacturer: (t && t.manufacturer) ? t.manufacturer : "",
                                firmware: (t && t.firmware) ? t.firmware : "",
                                hardware: (t && t.hardware) ? t.hardware : "",
                                flags: (t && t.flags) ? t.flags : "",
                                slotName: (t && t.slotName) ? t.slotName : ""
                            })
                        } else if (page.operation === "csr") {
                            // Запрос на сертификат: объекты токена не менялись; возврат
                            // к CsrPage — она покажет PEM из lastCsr (к списку не уходим).
                            pageStack.pop()
                        } else {
                            if (tokenSession.outcome === 1) {
                                tokenSession.updateNfcObjects() // обновить снимок после генерации/импорта
                                page.finishedOk()               // форма вернётся к списку объектов
                            }
                            pageStack.pop()
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
