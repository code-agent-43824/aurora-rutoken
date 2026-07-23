import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "generateKeyPage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string connection: "USB"   // "USB" — по кэшу PIN; "NFC" — через мастер
    // Экран списка объектов, откуда открыта форма: по успеху возвращаемся к нему
    // (правило проекта — после создания объекта показываем список, не форму) и
    // показываем на нём результат операции.
    property var objectsPage: null

    // Порядок кодов совпадает с пунктами ComboBox и с TokenSession::generateKeyPair.
    property var algoCodes: ["gost256", "gost512", "rsa2048", "rsa4096"]
    // Показывать результат только после попытки на этом экране (outcome общий с логином).
    property bool attempted: false
    property bool returnToList: false   // NFC: мастер завершил создание успешно
    property bool navigatedAway: false  // защита от повторного pop

    function doGenerate() {
        if (tokenSession.busy)
            return
        Qt.inputMethod.commit()
        if (page.connection === "NFC") {
            // По NFC — через мастер (взять токен → PIN → поднести → генерация).
            // По успешному завершению мастер сообщает finishedOk → возвращаемся
            // к списку объектов, когда форма снова станет активной.
            var wiz = pageStack.push(Qt.resolvedUrl("NfcConnectPage.qml"), {
                operation: "generate",
                algorithm: page.algoCodes[algoCombo.currentIndex],
                label: labelField.text
            })
            wiz.finishedOk.connect(function() { page.returnToList = true })
            return
        }
        if (!tokenSession.loggedIn)
            return
        page.attempted = true
        tokenSession.generateKeyPairCached(page.slotId,
                                           page.algoCodes[algoCombo.currentIndex],
                                           labelField.text)
    }

    // Вернуться к списку объектов и показать там результат (один раз).
    function goToList() {
        if (page.navigatedAway)
            return
        page.navigatedAway = true
        if (page.objectsPage)
            page.objectsPage.writeResultShown = true
        pageStack.pop()
    }

    // USB: операция идёт на этой (активной) странице — по успеху возвращаемся к
    // списку. Пока форма перекрыта (PIN-экран/мастер) — status не Active, не трогаем.
    Connections {
        target: tokenSession
        onChanged: {
            if (page.status === PageStatus.Active && page.attempted
                    && !tokenSession.busy && tokenSession.outcome === 1)
                page.goToList()
        }
    }

    // NFC: мастер завершился успехом (finishedOk) и его закрыли → форма снова
    // активна → возвращаемся к списку.
    onStatusChanged: {
        if (status === PageStatus.Active && page.returnToList)
            page.goToList()
    }

    // Вход по PIN (цифровой экран); используется запомненный PIN для генерации.
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
                title: qsTr("New key pair")
                description: qsTr("Generated on the token")
            }

            ComboBox {
                id: algoCombo
                width: parent.width
                label: qsTr("Algorithm and length")
                currentIndex: 0
                menu: ContextMenu {
                    MenuItem { text: qsTr("GOST R 34.10-2012, 256 bit") }
                    MenuItem { text: qsTr("GOST R 34.10-2012, 512 bit") }
                    MenuItem { text: qsTr("RSA 2048") }
                    MenuItem { text: qsTr("RSA 4096") }
                }
            }

            TextField {
                id: labelField
                width: parent.width
                label: qsTr("Key label")
                placeholderText: qsTr("For example, My GOST key")
                inputMethodHints: Qt.ImhNoPredictiveText
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.doGenerate()
            }

            // USB: требуется вход по PIN. Если не вошли — открыть цифровой экран PIN;
            // после входа PIN запоминается и генерация идёт без повторного ввода.
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
                text: tokenSession.busy ? qsTr("Generating…") : qsTr("Generate")
                enabled: !tokenSession.busy && (page.connection === "NFC" || tokenSession.loggedIn)
                onClicked: page.doGenerate()
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
                text: qsTr("The private key never leaves the token.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
