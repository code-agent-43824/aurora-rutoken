import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "generateKeyPage"
    allowedOrientations: Orientation.All

    property var slotId: 0

    // Порядок кодов совпадает с пунктами ComboBox и с TokenSession::generateKeyPair.
    property var algoCodes: ["gost256", "gost512", "rsa2048", "rsa4096"]
    // Показывать результат только после попытки на этом экране (outcome общий с логином).
    property bool attempted: false

    function doGenerate() {
        if (tokenSession.busy || !tokenSession.loggedIn)
            return
        Qt.inputMethod.commit()
        page.attempted = true
        tokenSession.generateKeyPairCached(page.slotId,
                                           page.algoCodes[algoCombo.currentIndex],
                                           labelField.text)
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

            // Требуется вход по PIN. Если не вошли — открыть цифровой экран PIN;
            // после входа PIN запоминается и генерация идёт без повторного ввода.
            Button {
                visible: !tokenSession.loggedIn
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Checking…") : qsTr("Enter PIN")
                enabled: !tokenSession.busy
                onClicked: page.openPinPad()
            }

            Label {
                visible: tokenSession.loggedIn
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("PIN is remembered")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Generating…") : qsTr("Generate")
                enabled: !tokenSession.busy && tokenSession.loggedIn
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
                visible: page.attempted && !tokenSession.busy && tokenSession.outcome === 1
                text: qsTr("Swipe back to see the new key in the list.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
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
