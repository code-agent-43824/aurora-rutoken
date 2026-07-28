import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

// Универсальный выбор исходного файла для CMS-подписи. Зависимость
// Sailfish.Pickers изолирована так же, как у импорта сертификата.
FilePickerPage {
    id: picker
    objectName: "signDataFilePickerPage"

    signal picked(string path)

    title: qsTr("Choose a file to sign")

    onSelectedContentPropertiesChanged: {
        if (selectedContentProperties && selectedContentProperties.filePath)
            picker.picked(selectedContentProperties.filePath)
    }
}
