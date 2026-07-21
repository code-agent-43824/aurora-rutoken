import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

// Изолированный выбор файла: только этот файл зависит от Sailfish.Pickers,
// поэтому экран импорта (с ручным вводом пути) работает независимо от него.
FilePickerPage {
    id: picker
    objectName: "certFilePickerPage"

    // Испускается с локальным путём выбранного файла; экран импорта его слушает.
    signal picked(string path)

    title: qsTr("Choose a certificate")

    onSelectedContentPropertiesChanged: {
        if (selectedContentProperties && selectedContentProperties.filePath)
            picker.picked(selectedContentProperties.filePath)
    }
}
