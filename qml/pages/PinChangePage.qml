import QtQuick 2.0
import Sailfish.Silica 1.0

// Управление PIN. mode: "user" | "so" | "unblock".
// Поток — прямая цепочка отдельных экранов ввода PIN, БЕЗ возврата к этому
// экрану между шагами и без списка введённых значений:
//   смена:  старый PIN → новый PIN → повтор нового; как только введён повтор —
//           сразу выполняем операцию (если новые совпали; иначе просим новый и
//           повтор заново, с подсказкой);
//   разблок.: один экран (PIN администратора) → сразу операция.
// Экраны ввода — PinPadPage с autoPop=false: PinPadPage сам не закрывается,
// навигацию ведёт этот контроллер. Первый шаг кладётся поверх этого экрана
// (push), каждый следующий ЗАМЕНЯЕТ предыдущий (pageStack.replace) — этот экран
// между шагами не показывается, и над ним всегда ровно один экран ввода, поэтому
// возврат за результатом — простой pageStack.pop() (без неоднозначности pop(page)).
// Жест «назад» с экрана ввода отменяет весь поток (см. onStatusChanged).
// Сам этот экран показывается только в конце — индикатор и результат.
Page {
    id: page
    objectName: "pinChangePage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string mode: "user"

    // Собранные значения.
    property string oldPin: ""
    property string newPin: ""
    property string confirmPin: ""

    property bool started: false    // первый показ уже открыл первый экран
    property bool attempted: false  // операция запущена → показываем результат

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

    // Данные собраны — закрываем экран ввода (над нами он один → простой pop) и
    // выполняем операцию; результат показываем уже здесь (индикатор → сообщение).
    function runOp() {
        page.attempted = true
        pageStack.pop()
        if (page.mode === "so")
            tokenSession.changeSoPin(page.slotId, page.oldPin, page.newPin)
        else if (page.mode === "unblock")
            tokenSession.unblockUserPin(page.slotId, page.oldPin)
        else
            tokenSession.changeUserPin(page.slotId, page.oldPin, page.newPin)
    }

    // Перезапуск после ошибки (например, неверный текущий PIN).
    function retry() {
        page.oldPin = ""
        page.newPin = ""
        page.confirmPin = ""
        page.attempted = false
        page.askOld()
    }

    // Старт цепочки при первом показе. Если экран снова стал активным ДО запуска
    // операции — значит пользователь вышел «назад» из ввода: отменяем всё.
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

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: tokenSession.busy
                visible: tokenSession.busy
                size: BusyIndicatorSize.Large
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
                font.pixelSize: Theme.fontSizeLarge
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.attempted && !tokenSession.busy && tokenSession.outcome === 1
                text: qsTr("Done")
                onClicked: pageStack.pop()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.attempted && !tokenSession.busy && tokenSession.outcome === -1
                text: qsTr("Try again")
                onClicked: page.retry()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                visible: !page.attempted
                text: page.mode === "unblock"
                      ? qsTr("The administrator resets the user PIN attempt counter; the user PIN itself stays the same.")
                      : qsTr("A wrong current PIN, entered several times, can lock the token.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
