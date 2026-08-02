import QtQuick 2.0
import Sailfish.Silica 1.0

// Мастер подключения по NFC (у NFC своя парадигма — токен держат недолго):
//   шаг 1 — взять токен в руки;
//   шаг 2 — ввод PIN (внешний PinPadPage);
//   шаг 3 — поднести токен к задней крышке (иллюстрация + прогресс), при
//           появлении NFC-слота выполняется операция;
//   шаг 4 — убрать токен, результат.
// operation: "connect" (вход + чтение), "generate", "import", "csr", "cms",
// "cpcontainer" (создание контейнера КриптоПро), "cpcsr" (запрос PKCS#10
// средствами КриптоПро).
// PIN по NFC НЕ
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
    // Повторный вход из уже открытого вида «Объекты»: PIN обязателен, после
    // обновления снимка возвращаемся к странице-инициатору.
    property bool requirePin: false
    property bool returnToCaller: false
    // Для operation="csr": ключевая пара по CKA_ID и поля Subject (DN).
    property string idHex: ""
    property var csrDn: null
    // Для operation="cms": выбранный сертификат и параметры файла/результата.
    property string cmsCertificateDerB64: ""
    property string cmsSourcePath: ""
    property bool cmsDetached: true
    property string cmsOutputDir: ""
    property string cmsOutputName: ""
    // Для operation="cpcontainer": считыватель, имя нового контейнера и тип
    // провайдера. Считыватель КриптоПро называется так же, как слот PKCS#11
    // (`ifd-nfcd-handler 00 00`), поэтому имя берётся у того же устройства.
    property string cpReaderName: ""
    property string cpContainerName: ""
    property int cpProviderType: 80
    // Для operation="cpcsr": полное имя существующего контейнера и поля Subject.
    property string cpContainer: ""
    property var cpSubject: null

    property int step: 1
    property string pin: ""
    property bool noPin: false      // подключение без входа (только публичные сертификаты)
    property bool started: false
    // Чтение КриптоПро запускается один раз за поднесение: на подключении —
    // чтобы увидеть контейнеры, после создания контейнера — чтобы новый объект
    // был виден без второго поднесения. Остальным операциям проход не нужен.
    property bool cryptoProStarted: false
    // Счётчик проходов на момент запуска: ждём именно свой результат, а не
    // первое попавшееся завершение чужого прохода.
    property int cryptoProSerial: -1
    // Собственная операция этого поднесения завершена — только после этого
    // канал PC/SC свободен для дополнительного прохода CAPI.
    property bool channelFree: false
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
        if (page.operation === "cms")
            return qsTr("Sign a file over NFC")
        if (page.operation === "cpcontainer")
            return qsTr("New CryptoPro container over NFC")
        if (page.operation === "cpcsr")
            return qsTr("CryptoPro certificate request over NFC")
        return qsTr("Connect over NFC")
    }

    // Операции, которые выполняет КриптоПро, а не PKCS#11: у них другой источник
    // состояния и результата, а канал PC/SC — тот же самый.
    function isCryptoProWrite() {
        return page.operation === "cpcontainer" || page.operation === "cpcsr"
    }

    function opBusy() {
        return page.isCryptoProWrite() ? cryptoProSession.createBusy
                                       : tokenSession.busy
    }

    function opOutcome() {
        return page.isCryptoProWrite() ? cryptoProSession.createOutcome
                                       : tokenSession.outcome
    }

    function opResult() {
        return page.isCryptoProWrite() ? cryptoProSession.createResult
                                       : tokenSession.result
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
        // Запись через КриптоПро идёт по тому же каналу PC/SC, что и PKCS#11:
        // пока по нему работает чужой проход, начинать нельзя — по NFC второй
        // одновременный доступ просто получит отказ.
        if (page.isCryptoProWrite()
                && (cryptoProSession.busy || cryptoProSession.createBusy))
            return
        var tok = page.findNfcToken()
        if (!tok)
            return
        page.started = true
        page.lastToken = tok
        if (page.operation === "cpcontainer")
            cryptoProSession.createContainer(
                        page.cpReaderName.length > 0 ? page.cpReaderName : tok.slotName,
                        page.cpContainerName, page.cpProviderType, page.pin)
        else if (page.operation === "cpcsr")
            cryptoProSession.createCertificateRequest(page.cpContainer,
                                                      page.cpProviderType,
                                                      page.pin, page.cpSubject)
        else if (page.operation === "generate")
            tokenSession.generateKeyPair(tok.slotId, page.pin, page.algorithm, page.label)
        else if (page.operation === "import")
            tokenSession.importCertificate(tok.slotId, page.pin, page.filePath, page.label)
        else if (page.operation === "csr")
            tokenSession.createCsr(tok.slotId, page.pin, page.idHex,
                                   page.csrDn.cn, page.csrDn.o, page.csrDn.ou, page.csrDn.c,
                                   page.csrDn.l, page.csrDn.st, page.csrDn.email)
        else if (page.operation === "cms")
            tokenSession.signCms(tok.slotId, page.pin, page.idHex,
                                 page.cmsCertificateDerB64, page.cmsSourcePath,
                                 page.cmsDetached, page.cmsOutputDir, page.cmsOutputName)
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

    // Проход CAPI в этом же поднесении нужен в двух случаях: при подключении —
    // чтобы увидеть контейнеры, и после успешного создания контейнера — чтобы
    // новый объект был виден без второго поднесения. Неудачное создание ничего
    // не изменило, перечитывать нечего.
    function needsCryptoPro() {
        if (!appSettings.cryptoProEnabled)
            return false
        return page.operation === "connect"
                || (page.operation === "cpcontainer"
                    && cryptoProSession.createOutcome === 1)
    }

    // Запускает чтение КриптоПро, когда это уместно и безопасно. Возвращает
    // true, если шаг «уберите устройство» ждёт КриптоПро (уже запущено или
    // ожидает освобождения канала).
    function maybeStartCryptoPro() {
        if (!page.needsCryptoPro() || !page.channelFree)
            return false
        if (page.cryptoProStarted)
            return true
        // Канал занят своей же операцией PKCS#11 или чужим проходом — ждём:
        // разбудит следующий сигнал tokenSession/cryptoProSession.
        if (tokenSession.busy || cryptoProSession.busy)
            return true
        page.cryptoProStarted = true
        page.cryptoProSerial = cryptoProSession.scanSerial
        cryptoProSession.refresh()
        return true
    }

    // Повтор после неудачи (например, токен убрали слишком рано): снова ждём
    // поднесения и выполняем ту же операцию с уже введённым PIN-кодом — без
    // повторного ввода PIN и данных.
    function retryNfc() {
        page.started = false
        page.cryptoProStarted = false
        page.cryptoProSerial = -1
        page.channelFree = false
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
    // При включённом КриптоПро на подключении дочитываем контейнеры в ЭТОМ ЖЕ
    // поднесении: после отрыва устройства CAPI читать уже нечего.
    Connections {
        target: tokenSession
        onChanged: {
            if (page.step !== 3)
                return
            // Операции КриптоПро идут мимо PKCS#11: их состояние здесь не
            // отражается, а старый outcome от прошлой операции завершил бы шаг.
            // Важно здесь лишь одно: канал освободился, запись можно начинать.
            if (page.isCryptoProWrite()) {
                if (!page.started)
                    page.tryRun()
                return
            }
            if (!page.started || tokenSession.busy
                    || (tokenSession.outcome === 0 && !page.noPin))
                return
            page.channelFree = true
            if (page.maybeStartCryptoPro())
                return
            page.step = 4
        }
    }
    // Завершение операции КриптоПро: сначала собственная запись этого поднесения,
    // затем — необязательный проход чтения, снимок которого сохраняем.
    Connections {
        target: cryptoProSession
        onChanged: {
            if (page.step !== 3)
                return
            if (!page.started) {
                // Устройство уже поднесено, но канал был занят чужим проходом.
                // Он закончился — пробуем снова, иначе ждать было бы нечего.
                page.tryRun()
                return
            }
            if (page.isCryptoProWrite() && !page.channelFree) {
                if (cryptoProSession.createBusy
                        || cryptoProSession.createOutcome === 0)
                    return
                page.channelFree = true
                if (page.maybeStartCryptoPro())
                    return
                page.step = 4
                return
            }
            if (cryptoProSession.busy)
                return
            if (!page.cryptoProStarted) {
                page.maybeStartCryptoPro()   // канал освободился — теперь можно
                return
            }
            if (cryptoProSession.scanSerial === page.cryptoProSerial)
                return                       // это завершение чужого прохода
            tokenSession.setNfcCryptoPro(cryptoProSession.certificates,
                                         cryptoProSession.containers)
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
                    text: qsTr("Take the Rutoken NFC device in your hand. You will hold it to the back of the phone in a moment.")
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
                    visible: page.operation === "connect" && !page.requirePin
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
                          ? qsTr("Keep holding the device — the operation is running.")
                          : qsTr("Hold the device to the back cover and keep it there.")
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
                    text: page.started ? qsTr("Device detected — working…")
                                       : qsTr("Waiting for the device…")
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
                    text: qsTr("You can remove the device now.")
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: page.opResult()
                    color: page.opOutcome() === 1 ? "#4caf50" : "#f44336"
                    font.pixelSize: Theme.fontSizeMedium
                }
                // Повтор при неудаче (например, токен убрали слишком рано) —
                // без повторного ввода PIN-кода/данных.
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !page.opBusy() && page.opOutcome() === -1
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
                            tokenSession.commitNfc(page.lastToken, !page.noPin)
                            if (page.returnToCaller) {
                                pageStack.pop()
                                return
                            }
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
                        } else if (page.operation === "csr" || page.operation === "cms"
                                   || page.operation === "cpcsr") {
                            // CSR/CMS не меняют объекты токена: возврат к форме,
                            // которая покажет сформированный запрос или путь подписи.
                            pageStack.pop()
                        } else if (page.operation === "cpcontainer") {
                            // Снимок КриптоПро обновлён в этом же поднесении,
                            // поэтому форма может сразу вернуться к списку
                            // объектов — новый контейнер там уже виден.
                            if (cryptoProSession.createOutcome === 1)
                                page.finishedOk()
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
