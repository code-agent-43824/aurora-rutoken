import QtQuick 2.0
import Sailfish.Silica 1.0

// Смена метки токена (vendor C_EX_SetTokenName) — требует PIN пользователя.
Page {
    id: page
    objectName: "tokenLabelPage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string currentLabel: ""
    property string userPin: ""
    property bool attempted: false

    function openPad() {
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            acceptText: qsTr("OK")
        })
        pad.entered.connect(function(value) { page.userPin = value })
    }

    function doApply() {
        if (tokenSession.busy || labelField.text.length === 0 || page.userPin.length === 0)
            return
        Qt.inputMethod.commit()
        page.attempted = true
        tokenSession.changeTokenLabel(page.slotId, page.userPin, labelField.text)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("Change token label") }

            TextField {
                id: labelField
                width: parent.width
                label: qsTr("Token label")
                placeholderText: qsTr("New token label")
                text: page.currentLabel
                inputMethodHints: Qt.ImhNoPredictiveText
                enabled: !tokenSession.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.doApply()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.userPin.length > 0
                      ? qsTr("User PIN") + ": ●●●●"
                      : qsTr("Enter user PIN")
                enabled: !tokenSession.busy
                onClicked: page.openPad()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tokenSession.busy ? qsTr("Applying…") : qsTr("Change label")
                enabled: !tokenSession.busy && labelField.text.length > 0 && page.userPin.length > 0
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
                text: qsTr("Changing the label requires the user PIN and does not erase the token.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
