import QtQuick 2.0
import Sailfish.Silica 1.0

// Управление PIN. mode:
//   "user"    — смена PIN пользователя (текущий + новый);
//   "so"      — смена PIN администратора/SO (текущий SO + новый SO);
//   "unblock" — разблокировка PIN пользователя администратором (SO + новый user).
// PIN вводится тем же цифровым экраном PinPadPage; у нового PIN — подтверждение.
Page {
    id: page
    objectName: "pinChangePage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string mode: "user"

    property string pin1: ""   // текущий user PIN / текущий SO PIN / SO PIN
    property string pin2: ""   // новый PIN
    property string pin2c: ""  // подтверждение нового PIN
    property bool attempted: false

    function titleText() {
        if (mode === "so") return qsTr("Change admin PIN")
        if (mode === "unblock") return qsTr("Unblock user PIN")
        return qsTr("Change user PIN")
    }
    function pin1Label() {
        if (mode === "so") return qsTr("Current admin PIN")
        if (mode === "unblock") return qsTr("Administrator (SO) PIN")
        return qsTr("Current user PIN")
    }
    function pin2Label() {
        if (mode === "so") return qsTr("New admin PIN")
        return qsTr("New user PIN")
    }
    function dots(s) {
        var out = ""
        for (var i = 0; i < s.length; ++i) out += "●"
        return out
    }
    function matchOk() {
        return pin2.length > 0 && pin2 === pin2c
    }
    function canApply() {
        // Разблокировка требует только PIN администратора (нового PIN нет).
        return !tokenSession.busy && pin1.length > 0 && (mode === "unblock" || matchOk())
    }

    function openPad(which, heading) {
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: heading,
            acceptText: qsTr("OK")
        })
        pad.entered.connect(function(value) {
            if (which === "pin1") page.pin1 = value
            else if (which === "pin2") page.pin2 = value
            else page.pin2c = value
        })
    }

    function doApply() {
        if (!page.canApply())
            return
        page.attempted = true
        if (page.mode === "so")
            tokenSession.changeSoPin(page.slotId, page.pin1, page.pin2)
        else if (page.mode === "unblock")
            tokenSession.unblockUserPin(page.slotId, page.pin1)
        else
            tokenSession.changeUserPin(page.slotId, page.pin1, page.pin2)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader { title: page.titleText() }

            // Текущий PIN (пользователя или SO).
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.pin1.length > 0
                      ? page.pin1Label() + ": " + page.dots(page.pin1)
                      : page.pin1Label()
                enabled: !tokenSession.busy
                onClicked: page.openPad("pin1", page.pin1Label())
            }

            // Новый PIN (не нужен при разблокировке — там только сброс счётчика).
            Button {
                visible: page.mode !== "unblock"
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.pin2.length > 0
                      ? page.pin2Label() + ": " + page.dots(page.pin2)
                      : page.pin2Label()
                enabled: !tokenSession.busy
                onClicked: page.openPad("pin2", page.pin2Label())
            }

            // Подтверждение нового PIN.
            Button {
                visible: page.mode !== "unblock"
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.pin2c.length > 0
                      ? qsTr("Confirm new PIN") + ": " + page.dots(page.pin2c)
                      : qsTr("Confirm new PIN")
                enabled: !tokenSession.busy
                onClicked: page.openPad("pin2c", qsTr("Confirm new PIN"))
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: page.mode !== "unblock" && page.pin2.length > 0 && page.pin2c.length > 0
                         && page.pin2 !== page.pin2c
                text: qsTr("The new PINs do not match")
                color: "#f44336"
                font.pixelSize: Theme.fontSizeSmall
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Applying…")
                      : (page.mode === "unblock" ? qsTr("Unblock") : qsTr("Change PIN"))
                enabled: page.canApply()
                onClicked: page.doApply()
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
