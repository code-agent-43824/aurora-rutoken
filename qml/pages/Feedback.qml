import QtQuick 2.0
import Nemo.Ngf 1.0

// Изолированная зависимость Nemo.Ngf (системные звуки/вибрация). Загружается
// через Loader: если модуль на Авроре недоступен, элемент просто не создастся
// и звук молча не проиграется — экран NFC при этом работает.
Item {
    id: root
    function play(eventName) {
        ngf.event = eventName
        ngf.play()
    }
    NonGraphicalFeedback {
        id: ngf
        event: "general"
    }
}
