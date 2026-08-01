import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    objectName: "settingsPage"
    allowedOrientations: Orientation.All

    // Типы ГОСТ-провайдеров КриптоПро в порядке показа. Те же номера знает и
    // backend (AppSettings::knownProviderTypes).
    readonly property var providerModel: [
        { type: 80, name: qsTr("GOST R 34.10-2012 (256)"), hint: qsTr("Main provider, type 80") },
        { type: 81, name: qsTr("GOST R 34.10-2012 (512)"), hint: qsTr("Type 81") },
        { type: 75, name: qsTr("GOST R 34.10-2001"), hint: qsTr("Legacy algorithm, type 75") }
    ]

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

    function providerIsLastEnabled(type) {
        return appSettings.cryptoProProviderTypes.length === 1
                && page.providerEnabled(type)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width

            PageHeader {
                title: qsTr("Settings")
            }

            TextSwitch {
                width: parent.width
                text: qsTr("Use CryptoPro CSP")
                description: qsTr("When disabled, CryptoPro libraries are not loaded")
                checked: appSettings.cryptoProEnabled
                onClicked: appSettings.cryptoProEnabled = checked
            }

            SectionHeader { text: qsTr("CryptoPro providers") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Containers are read and created with the selected providers only. Every extra provider is a separate poll of the token, so selecting several of them degrades performance badly — especially over NFC.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            // Последний включённый провайдер не выключается: пустой набор
            // означал бы включённый КриптоПро, который ничего не читает.
            Repeater {
                model: page.providerModel

                TextSwitch {
                    width: parent.width
                    text: modelData.name
                    description: modelData.hint
                    automaticCheck: false
                    checked: page.providerEnabled(modelData.type)
                    enabled: !page.providerIsLastEnabled(modelData.type)
                    onClicked: appSettings.setProviderTypeEnabled(modelData.type, !checked)
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
