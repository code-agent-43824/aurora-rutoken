import QtQuick 2.0
import QtMultimedia 5.6

// Короткие звуки соединения/рассоединения по NFC из вложенных WAV-файлов
// (через QtMultimedia). Загружается из NfcConnectPage через Loader — если
// QtMultimedia недоступен на Авроре, элемент просто не создастся и экран NFC
// продолжит работать без звука.
Item {
    id: root

    // Раскладка на устройстве: qml/pages/Feedback.qml и sounds/*.wav лежат под
    // одним каталогом приложения, поэтому путь «../../sounds/…».
    function play(eventName) {
        if (eventName === "positive")
            connectFx.play()
        else
            disconnectFx.play()
    }

    SoundEffect {
        id: connectFx
        source: Qt.resolvedUrl("../../sounds/nfc-connect.wav")
    }
    SoundEffect {
        id: disconnectFx
        source: Qt.resolvedUrl("../../sounds/nfc-disconnect.wav")
    }
}
