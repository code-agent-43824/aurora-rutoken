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

    property int providerType: 80          // 80 — ГОСТ-2012 256, 81 — ГОСТ-2012 512
    property bool attempted: false
    property bool returnedToList: false

    function algorithmName() {
        return page.providerType === 81 ? qsTr("GOST R 34.10-2012 (512)")
                                        : qsTr("GOST R 34.10-2012 (256)")
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
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            subtitle: page.deviceLabel.length > 0 ? page.deviceLabel : qsTr("Rutoken"),
            acceptText: qsTr("Create")
        })
        pad.entered.connect(function(pin) {
            page.attempted = true
            cryptoProSession.createContainer(page.readerName, name, page.providerType, pin)
        })
    }

    // Успех — возвращаемся к списку объектов, результат показывается там.
    Connections {
        target: cryptoProSession
        onChanged: {
            if (page.status !== PageStatus.Active || !page.attempted)
                return
            if (!cryptoProSession.createBusy && cryptoProSession.createOutcome === 1)
                page.goToList()
        }
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

            ComboBox {
                width: parent.width
                label: qsTr("Algorithm")
                currentIndex: page.providerType === 81 ? 1 : 0
                menu: ContextMenu {
                    MenuItem { text: qsTr("GOST R 34.10-2012 (256)") }
                    MenuItem { text: qsTr("GOST R 34.10-2012 (512)") }
                }
                onCurrentIndexChanged: page.providerType = currentIndex === 1 ? 81 : 80
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
