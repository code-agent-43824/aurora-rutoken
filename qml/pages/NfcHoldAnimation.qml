import QtQuick 2.0
import Sailfish.Silica 1.0

// Встроенная иллюстрация подключения по NFC. Состояния:
//   "searching"  — токен подъезжает/отъезжает по кругу (ищем токен);
//   "connected"  — токен прижат к задней крышке и держится там (идёт обмен);
//   "removing"   — токен убирают от телефона (операция завершена).
// Никаких внешних файлов; позиция токена — биндинг с интерполяцией по approach,
// устойчивый к изменению ширины.
Item {
    id: root
    implicitHeight: Theme.itemSizeHuge * 2

    property real approach: 0                 // 0 — далеко, 1 — у задней крышки
    property string animState: "searching"

    SequentialAnimation {
        id: searchAnim
        running: root.animState === "searching" && root.visible
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "approach"; from: 0; to: 1; duration: 1400; easing.type: Easing.InOutQuad }
        PauseAnimation { duration: 700 }
        NumberAnimation { target: root; property: "approach"; from: 1; to: 0; duration: 900; easing.type: Easing.InOutQuad }
        PauseAnimation { duration: 300 }
    }

    NumberAnimation {
        id: removeAnim
        target: root; property: "approach"; to: 0; duration: 1000; easing.type: Easing.InOutQuad
    }

    onAnimStateChanged: {
        if (root.animState === "connected") {
            searchAnim.stop()
            root.approach = 1
        } else if (root.animState === "removing") {
            searchAnim.stop()
            removeAnim.restart()
        } else {
            root.approach = 0
        }
    }

    // Телефон (задняя крышка).
    Rectangle {
        id: phone
        height: root.height * 0.86
        width: height * 0.5
        radius: width * 0.14
        anchors.verticalCenter: parent.verticalCenter
        x: root.width * 0.14
        color: "transparent"
        border.color: Theme.highlightColor
        border.width: 2

        // Зона NFC-антенны.
        Rectangle {
            id: nfcZone
            width: parent.width * 0.5
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.14
            color: "transparent"
            border.color: Theme.secondaryHighlightColor
            border.width: 1
            Label {
                anchors.centerIn: parent
                text: "NFC"
                font.pixelSize: Theme.fontSizeTiny
                color: Theme.secondaryHighlightColor
            }
        }
    }

    // Пульсирующие волны (активны, пока ищем или держим; при removing скрыты).
    Repeater {
        model: 3
        delegate: Rectangle {
            width: phone.width * 0.5
            height: width
            radius: width / 2
            color: "transparent"
            border.color: Theme.highlightColor
            border.width: 2
            x: phone.x + phone.width / 2 - width / 2
            y: phone.y + nfcZone.y + nfcZone.height / 2 - height / 2
            visible: root.animState !== "removing"
            opacity: 0
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: root.visible && root.animState !== "removing"
                PauseAnimation { duration: index * 500 }
                NumberAnimation { from: 0.8; to: 0.0; duration: 1500 }
                PauseAnimation { duration: (2 - index) * 500 }
            }
            SequentialAnimation on scale {
                loops: Animation.Infinite
                running: root.visible && root.animState !== "removing"
                PauseAnimation { duration: index * 500 }
                NumberAnimation { from: 0.6; to: 2.4; duration: 1500 }
                PauseAnimation { duration: (2 - index) * 500 }
            }
        }
    }

    // Токен (карточка).
    Rectangle {
        id: token
        height: root.height * 0.34
        width: height * 1.55
        radius: Theme.paddingMedium
        anchors.verticalCenter: phone.verticalCenter
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.35)
        border.color: Theme.highlightColor
        border.width: 1
        x: (root.width * 0.80) * (1 - root.approach)
           + (phone.x + phone.width * 0.5) * root.approach
        Label {
            anchors.centerIn: parent
            text: "Rutoken"
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.primaryColor
        }
    }
}
