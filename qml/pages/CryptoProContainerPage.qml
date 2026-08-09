import QtQuick 2.0
import Sailfish.Silica 1.0

// Создание ключевого контейнера КриптоПро на выбранном устройстве (v1.3).
// Пользователь задаёт имя и алгоритм, вводит PIN-код, после чего в отдельном
// helper-процессе создаётся контейнер и генерируется НЕЭКСПОРТИРУЕМАЯ ключевая
// пара. При сбое после создания контейнера backend откатывает только его.
Page {
    id: page
    objectName: "cryptoProContainerPage"
    allowedOrientations: Orientation.All

    // Считыватель устройства, на котором создаём контейнер, и экран объектов,
    // к которому возвращаемся по правилу навигации после создания.
    property string readerName: ""
    property string deviceLabel: ""
    property var objectsPage: null
    // "USB" — операция идёт прямо отсюда; "NFC" — через мастер поднесения.
    property string connection: "USB"

    // 80 — ГОСТ-2012/256, 81 — ГОСТ-2012/512, 75 — ГОСТ-2001. Создавать можно
    // только теми провайдерами, которыми приложение читает: иначе получился бы
    // контейнер, которого оно само не покажет. Выключенные в настройках
    // провайдеры остаются в списке неактивными — видно, что они есть.
    // Порядок обязан совпадать с порядком пунктов меню: по нему выставляется
    // currentIndex.
    readonly property var providerTypes: [80, 81, 75]

    property int providerType: 80
    property bool attempted: false
    property bool returnedToList: false
    // NFC: мастер завершился успехом — возвращаемся к списку, когда форма снова
    // станет активной (пока мастер сверху, pageStack трогать нельзя).
    property bool pendingReturn: false

    // Читаем список-свойство, а не Q_INVOKABLE: только у свойства есть сигнал
    // изменения, по которому QML пересчитает привязку.
    function providerEnabled(type) {
        var list = appSettings.cryptoProProviderTypes
        for (var i = 0; i < list.length; ++i) {
            if (list[i] === type)
                return true
        }
        return false
    }

    function indexOfType(type) {
        var index = page.providerTypes.indexOf(type)
        return index < 0 ? 0 : index
    }

    // Выбирается ОДИН из трёх режимов работы носителя — CSP, PKCS#11, ФКН.
    // Другого носителя выбрать нельзя: контейнер создаётся только на
    // подключённом сейчас токене. Списка считывателей на экране нет намеренно —
    // программные хранилища (реестр, каталог, облако) приложению не нужны.
    property string modeKey: ""

    function modeOptions() {
        var list = cryptoProSession.mediaModes
        return list ? list : []
    }

    // Режим доступен, если провайдер назвал для него носитель или считыватель.
    // Отдельно закрыт CSP по NFC: пассивные контейнеры по этому интерфейсу не
    // видны — так устроен сам носитель, это не выбор приложения.
    function modeAvailable(row) {
        if (!row.target || row.target.length === 0)
            return false
        return !(page.connection === "NFC" && row.mode === "csp")
    }

    function modeUnavailableHint(row) {
        if (page.connection === "NFC" && row.mode === "csp")
            return qsTr("not available over NFC")
        return qsTr("not offered by the device")
    }

    function anyModeAvailable() {
        var rows = page.modeOptions()
        for (var i = 0; i < rows.length; ++i) {
            if (page.modeAvailable(rows[i]))
                return true
        }
        return false
    }

    function selectedMode() {
        var rows = page.modeOptions()
        for (var i = 0; i < rows.length; ++i) {
            if (rows[i].mode === page.modeKey && page.modeAvailable(rows[i]))
                return rows[i]
        }
        return null
    }

    // Считыватель у всех режимов один и тот же — это установлено замером.
    function targetNick() {
        var row = page.selectedMode()
        return row && row.reader.length > 0 ? row.reader : page.readerName
    }

    // Уникальное имя носителя: только оно отличает режимы друг от друга. Пусто
    // — режим не различим, и его выберет провайдер.
    function targetMedium() {
        var row = page.selectedMode()
        return row ? row.unique : ""
    }

    // Открываемся на активном токене: именно этот режим документация Рутокена
    // предписывает выбирать при генерации ключей (dev.rutoken.ru, «Неизвлекаемые
    // ключи на Рутокенах в КриптоПро CSP 5.0 R2»). Нет его — первый доступный.
    function defaultModeKey() {
        var rows = page.modeOptions()
        var first = ""
        for (var i = 0; i < rows.length; ++i) {
            if (!page.modeAvailable(rows[i]))
                continue
            if (rows[i].mode === "active")
                return "active"
            if (first.length === 0)
                first = rows[i].mode
        }
        return first
    }

    // Ранее выбранный провайдер мог быть выключен в настройках, поэтому форма
    // открывается на первом разрешённом варианте.
    Component.onCompleted: {
        if (!page.providerEnabled(page.providerType))
            page.providerType = appSettings.firstEnabledProviderType()
        algorithmBox.currentIndex = page.indexOfType(page.providerType)
        page.modeKey = page.defaultModeKey()
    }

    function suggestedName() {
        // Имя должно быть уникальным на устройстве; время даёт простую основу.
        return "rutoken-" + Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss")
    }

    function goToList() {
        if (page.returnedToList)
            return
        page.returnedToList = true
        if (page.objectsPage)
            page.objectsPage.writeResultShown = true
        pageStack.pop()
    }

    function start() {
        if (cryptoProSession.createBusy)
            return
        var name = nameField.text.trim()
        if (name.length === 0)
            name = page.suggestedName()
        if (page.connection === "NFC") {
            // По NFC — через мастер (взять устройство → PIN → поднести →
            // создание). PIN-код спрашивает мастер, поэтому здесь его не просим.
            var wiz = pageStack.push(Qt.resolvedUrl("NfcConnectPage.qml"), {
                operation: "cpcontainer",
                cpReaderName: page.targetNick(),
                cpMediumName: page.targetMedium(),
                cpContainerName: name,
                cpProviderType: page.providerType
            })
            wiz.finishedOk.connect(function() { page.pendingReturn = true })
            return
        }
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            subtitle: page.deviceLabel.length > 0 ? page.deviceLabel : qsTr("Rutoken"),
            acceptText: qsTr("Create")
        })
        pad.entered.connect(function(pin) {
            page.attempted = true
            cryptoProSession.createContainer(page.targetNick(), page.targetMedium(),
                                             name, page.providerType, pin)
        })
    }

    // Успех — возвращаемся к списку объектов, результат показывается там.
    Connections {
        target: cryptoProSession
        onChanged: {
            // Список режимов приходит с проходом, а он мог завершиться уже после
            // открытия формы; если выбранного режима в нём нет — переходим на
            // умолчание, иначе кнопка создавала бы контейнер не туда.
            var rows = page.modeOptions()
            var stillThere = false
            for (var i = 0; i < rows.length; ++i) {
                if (rows[i].mode === page.modeKey && page.modeAvailable(rows[i]))
                    stillThere = true
            }
            if (!stillThere)
                page.modeKey = page.defaultModeKey()
            if (page.status !== PageStatus.Active || !page.attempted)
                return
            if (!cryptoProSession.createBusy && cryptoProSession.createOutcome === 1) {
                // Набор контейнеров на носителе изменился, а список объектов
                // берёт их из результата прошлого прохода — без перечитывания
                // новый контейнер появился бы только после переподключения
                // устройства. По NFC перечитывание делает мастер, в том же
                // поднесении; сюда попадает только путь USB.
                cryptoProSession.refresh()
                page.goToList()
            }
        }
    }

    // NFC: мастер закрыли после успеха → форма снова активна → к списку.
    onStatusChanged: {
        if (status === PageStatus.Active && page.pendingReturn)
            page.goToList()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: qsTr("New CryptoPro container")
                description: page.deviceLabel.length > 0 ? page.deviceLabel : qsTr("Rutoken")
            }

            TextField {
                id: nameField
                width: parent.width
                label: qsTr("Container name")
                placeholderText: page.suggestedName()
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // Ровно три режима и ничего кроме них. Список, а не выпадающее
            // меню: под каждым пунктом показано имя, которым провайдер назвал
            // этот режим на устройстве, — по нему видно, куда пойдёт контейнер,
            // и с чем сверять режим в карточке созданного объекта.
            SectionHeader { text: qsTr("Operating mode") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("The container is created on the connected token. Modes the device did not offer are shown but cannot be selected.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Repeater {
                model: page.modeOptions()

                BackgroundItem {
                    width: parent.width
                    height: modeColumn.height + 2 * Theme.paddingMedium
                    enabled: page.modeAvailable(modelData)
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: page.modeKey = modelData.mode

                    Column {
                        id: modeColumn
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter

                        Label {
                            width: parent.width
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            text: (page.modeKey === modelData.mode ? "\u25cf " : "\u25cb ")
                                  + modelData.title
                            color: page.modeKey === modelData.mode
                                   ? Theme.highlightColor : Theme.primaryColor
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Label {
                            width: parent.width
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            text: "      " + (page.modeAvailable(modelData)
                                              ? modelData.target
                                              : page.modeUnavailableHint(modelData))
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }

                        // Считыватель показывается отдельно: он у всех режимов
                        // один и тот же, а режим задаёт уникальное имя выше.
                        // Если уникального имени нет, режим выберет провайдер —
                        // об этом сказано прямо, а не умолчанием.
                        Label {
                            width: parent.width
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            visible: page.modeAvailable(modelData)
                                     && modelData.reader !== modelData.target
                            text: "      " + modelData.reader
                                  + (modelData.unique.length > 0
                                     ? "" : qsTr(" — mode chosen by the provider"))
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }
                    }
                }
            }

            // Сырой вывод перечисления. Правило адресации дважды оказалось
            // догадкой, поэтому то, что вернуло устройство, должно быть видно
            // целиком — включая строки, которые форма отбрасывает.
            SectionHeader {
                text: qsTr("What the device returned")
                visible: cryptoProSession.enumeration.length > 0
            }

            Repeater {
                model: cryptoProSession.enumeration

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: modelData.kind + ": " + modelData.nick
                          + (modelData.name.length > 0 ? "  |  " + modelData.name : "")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }

            // Устройство не назвало ни одного режима: создавать всё равно есть
            // где — на подключённом токене, — но режим выберет провайдер, и
            // обещать конкретный здесь нельзя.
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                visible: !page.anyModeAvailable()
                text: qsTr("The device did not report any mode. The container will be created on the connected token and the provider picks the mode — it is then shown on the object card.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            ComboBox {
                id: algorithmBox
                width: parent.width
                label: qsTr("Algorithm")
                description: qsTr("Providers switched off in the settings are shown but cannot be selected")
                // Пункты перечислены явно: Silica ComboBox сопоставляет
                // currentIndex с детьми меню по порядку, и лишний Repeater
                // среди них сбил бы нумерацию. Выключенный пункт остаётся на
                // месте и виден, просто приглушён и не нажимается.
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("GOST R 34.10-2012 (256)")
                        enabled: page.providerEnabled(80)
                        opacity: enabled ? 1.0 : 0.4
                        onClicked: page.providerType = 80
                    }
                    MenuItem {
                        text: qsTr("GOST R 34.10-2012 (512)")
                        enabled: page.providerEnabled(81)
                        opacity: enabled ? 1.0 : 0.4
                        onClicked: page.providerType = 81
                    }
                    MenuItem {
                        text: qsTr("GOST R 34.10-2001")
                        enabled: page.providerEnabled(75)
                        opacity: enabled ? 1.0 : 0.4
                        onClicked: page.providerType = 75
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("The private key is generated inside the device and is not exportable. If the key pair cannot be created, the container is removed automatically.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: cryptoProSession.createBusy ? qsTr("Creating…") : qsTr("Create container")
                enabled: !cryptoProSession.createBusy
                         && page.providerEnabled(page.providerType)
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
        }

        VerticalScrollDecorator {}
    }
}
