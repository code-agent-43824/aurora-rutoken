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

    // Два уровня, как в диалоге выбора ключевого носителя КриптоПро: сначала
    // СЧИТЫВАТЕЛЬ, затем РЕЖИМ РАБОТЫ — и режим это имя носителя
    // (`rutoken_ecp_…` — CSP, `pkcs11_rutoken_ecp_…` — активный токен,
    // `rutoken_fkc_…` — ФКН). Оба списка приходят с устройства, ничего не
    // выдумывается: неверное имя создало бы контейнер не там.
    property string readerNick: page.readerName
    property string mediaNick: ""

    function optionsFrom(list, fallback) {
        var out = []
        var source = list ? list : []
        for (var i = 0; i < source.length; ++i) {
            var nick = source[i].nick ? source[i].nick : ""
            if (nick.length === 0)
                continue
            out.push({
                nick: nick,
                title: source[i].mode && source[i].mode.length > 0
                       ? source[i].mode + " (" + nick + ")" : nick
            })
        }
        // Считыватель текущего устройства обязан быть в списке даже если
        // перечисление ничего не вернуло: иначе создавать будет негде.
        var known = false
        for (var j = 0; j < out.length; ++j)
            known = known || out[j].nick === fallback
        if (!known && fallback.length > 0)
            out.unshift({ nick: fallback, title: fallback })
        return out
    }

    function readerOptions() {
        return page.optionsFrom(cryptoProSession.readers, page.readerName)
    }

    function modeOptions() {
        var out = [{ nick: "", title: qsTr("chosen by the provider") }]
        var media = page.optionsFrom(cryptoProSession.media, "")
        for (var i = 0; i < media.length; ++i)
            out.push(media[i])
        return out
    }

    // Куда именно создавать: если режим выбран — на его носителе, иначе на
    // считывателе. Провайдер выберет режим сам, и он будет виден в карточке.
    function targetNick() {
        return page.mediaNick.length > 0 ? page.mediaNick : page.readerNick
    }

    // Ранее выбранный провайдер мог быть выключен в настройках, поэтому форма
    // открывается на первом разрешённом варианте.
    Component.onCompleted: {
        if (!page.providerEnabled(page.providerType))
            page.providerType = appSettings.firstEnabledProviderType()
        algorithmBox.currentIndex = page.indexOfType(page.providerType)
        if (page.readerNick.length === 0) {
            var readers = page.readerOptions()
            page.readerNick = readers.length > 0 ? readers[0].nick : ""
        }
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
            cryptoProSession.createContainer(page.targetNick(), name, page.providerType, pin)
        })
    }

    // Успех — возвращаемся к списку объектов, результат показывается там.
    Connections {
        target: cryptoProSession
        onChanged: {
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

            // Порядок как в диалоге КриптоПро: считыватель, затем режим работы.
            // Пункты — только то, что провайдер перечислил на этом устройстве.
            // Списки, а не выпадающие меню: число пунктов заранее неизвестно, а
            // Silica ComboBox сопоставляет выбор с детьми меню по порядку.
            SectionHeader { text: qsTr("Reader") }

            Repeater {
                model: page.readerOptions()

                BackgroundItem {
                    width: parent.width
                    height: readerLabel.height + 2 * Theme.paddingMedium
                    onClicked: page.readerNick = modelData.nick

                    Label {
                        id: readerLabel
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: (page.readerNick === modelData.nick ? "\u25cf " : "\u25cb ") + modelData.title
                        color: page.readerNick === modelData.nick
                               ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            SectionHeader { text: qsTr("Operating mode") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("The mode is the medium: CSP, PKCS#11 or FKN. Leave it unset to let the provider choose — the mode it picked is then shown on the object card.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Repeater {
                model: page.modeOptions()

                BackgroundItem {
                    width: parent.width
                    height: modeLabel.height + 2 * Theme.paddingMedium
                    onClicked: page.mediaNick = modelData.nick

                    Label {
                        id: modeLabel
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: (page.mediaNick === modelData.nick ? "\u25cf " : "\u25cb ") + modelData.title
                        color: page.mediaNick === modelData.nick
                               ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
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
