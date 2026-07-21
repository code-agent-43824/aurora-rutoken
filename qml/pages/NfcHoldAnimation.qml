import QtQuick 2.0
import Sailfish.Silica 1.0

// Встроенная иллюстрация: контур телефона (задняя крышка) с зоной NFC,
// пульсирующие волны и карточка-токен, подъезжающая к задней крышке.
// Никаких внешних файлов; анимация устойчива к изменению ширины (позиция
// токена — биндинг с интерполяцией по approach).
Item {
    id: root
    implicitHeight: Theme.itemSizeHuge * 2

    // 0 — токен далеко, 1 — токен у задней крышки.
    property real approach: 0

    SequentialAnimation on approach {
        loops: Animation.Infinite
        running: root.visible
        NumberAnimation { from: 0; to: 1; duration: 1400; easing.type: Easing.InOutQuad }
        PauseAnimation { duration: 700 }
        NumberAnimation { from: 1; to: 0; duration: 900; easing.type: Easing.InOutQuad }
        PauseAnimation { duration: 300 }
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

        // Зона NFC-антенны (верхняя часть задней крышки).
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

    // Пульсирующие волны от зоны NFC.
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
            opacity: 0
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: root.visible
                PauseAnimation { duration: index * 500 }
                NumberAnimation { from: 0.8; to: 0.0; duration: 1500 }
                PauseAnimation { duration: (2 - index) * 500 }
            }
            SequentialAnimation on scale {
                loops: Animation.Infinite
                running: root.visible
                PauseAnimation { duration: index * 500 }
                NumberAnimation { from: 0.6; to: 2.4; duration: 1500 }
                PauseAnimation { duration: (2 - index) * 500 }
            }
        }
    }

    // Токен (карточка), подъезжает к задней крышке и обратно.
    Rectangle {
        id: token
        height: root.height * 0.34
        width: height * 1.55
        radius: Theme.paddingMedium
        anchors.verticalCenter: phone.verticalCenter
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.35)
        border.color: Theme.highlightColor
        border.width: 1
        // Интерполяция позиции: далеко (0) → у крышки (1). Биндинг пересчитывается
        // и при анимации approach, и при изменении ширины root.
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
