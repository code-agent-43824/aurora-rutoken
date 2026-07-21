import QtQuick 2.0
import Sailfish.Silica 1.0

// Отдельный экран ввода PIN: по умолчанию цифровая клавиатура, с переключением
// в текстовый режим (обычная клавиатура ОС). По готовности испускает entered(pin)
// и сам закрывается. Переиспользуется USB-входом и NFC-мастером.
Page {
    id: page
    objectName: "pinPadPage"
    allowedOrientations: Orientation.All

    property string heading: qsTr("User PIN")
    property string subtitle: ""
    property string acceptText: qsTr("Log in")
    property string pin: ""
    property bool textMode: false
    property bool reveal: false

    signal entered(string pin)

    function accept() {
        if (page.pin.length === 0)
            return
        Qt.inputMethod.commit()
        var value = page.pin
        page.entered(value)
        pageStack.pop()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader { title: page.heading }

            Label {
                visible: page.subtitle.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: page.subtitle
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
            }

            // Введённый PIN: маска (●) или цифры.
            Label {
                visible: !page.textMode
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    if (page.pin.length === 0)
                        return "—"
                    if (page.reveal)
                        return page.pin
                    var s = ""
                    for (var i = 0; i < page.pin.length; ++i)
                        s += "●"
                    return s
                }
                font.pixelSize: Theme.fontSizeExtraLarge
                color: Theme.highlightColor
            }

            // Всегда занимает своё место в раскладке (visible при цифровом режиме),
            // а до первой цифры лишь прозрачна — чтобы её появление не сдвигало
            // клавиатуру вниз (кнопки не «спрыгивают» из-под пальца).
            Button {
                visible: !page.textMode
                opacity: page.pin.length > 0 ? 1.0 : 0.0
                enabled: page.pin.length > 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.reveal ? qsTr("Hide") : qsTr("Show")
                onClicked: page.reveal = !page.reveal
            }

            // Текстовый режим: клавиатура ОС.
            TextField {
                id: textField
                visible: page.textMode
                width: parent.width
                label: page.heading
                placeholderText: qsTr("Enter user PIN")
                echoMode: page.reveal ? TextInput.Normal : TextInput.Password
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                text: page.pin
                onTextChanged: if (page.textMode && text !== page.pin) page.pin = text
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.accept()
            }

            // Цифровая клавиатура 3×4: 1–9, [Abc → текст], 0, [← стереть].
            Grid {
                visible: !page.textMode
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                spacing: Theme.paddingMedium

                Repeater {
                    model: [
                        { t: "d", v: "1" }, { t: "d", v: "2" }, { t: "d", v: "3" },
                        { t: "d", v: "4" }, { t: "d", v: "5" }, { t: "d", v: "6" },
                        { t: "d", v: "7" }, { t: "d", v: "8" }, { t: "d", v: "9" },
                        { t: "abc", v: "" }, { t: "d", v: "0" }, { t: "back", v: "" }
                    ]
                    delegate: BackgroundItem {
                        id: key
                        width: Math.min(Theme.itemSizeExtraLarge,
                                        (page.width - 4 * Theme.paddingMedium) / 3)
                        height: Theme.itemSizeLarge
                        onClicked: {
                            if (modelData.t === "d")
                                page.pin = page.pin + modelData.v
                            else if (modelData.t === "back") {
                                if (page.pin.length > 0)
                                    page.pin = page.pin.substring(0, page.pin.length - 1)
                            } else if (modelData.t === "abc") {
                                page.textMode = true
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Theme.paddingSmall
                            radius: Theme.paddingMedium
                            color: key.highlighted
                                   ? Theme.rgba(Theme.highlightBackgroundColor, 0.4)
                                   : Theme.rgba(Theme.highlightBackgroundColor, 0.12)
                        }
                        Label {
                            anchors.centerIn: parent
                            text: modelData.t === "d" ? modelData.v
                                  : (modelData.t === "back" ? "←" : "Abc")
                            font.pixelSize: modelData.t === "d" ? Theme.fontSizeExtraLarge
                                                               : Theme.fontSizeLarge
                            color: Theme.primaryColor
                        }
                    }
                }
            }

            Button {
                visible: page.textMode
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Numeric keypad")
                onClicked: page.textMode = false
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.acceptText
                enabled: page.pin.length > 0
                onClicked: page.accept()
            }
        }

        VerticalScrollDecorator {}
    }
}
