import QtQuick 2.0
import Sailfish.Silica 1.0

// Единый экран токена с переключателем вида вверху: «Свойства» (по умолчанию —
// данные токена и административные функции: смена PIN-кодов, разблокировка,
// смена метки) и «Объекты» (вход, сертификаты, ключи и связанные
// операции: генерация, импорт, экспорт, удаление, запрос на сертификат). Оба
// вида одинаково быстро доступны, отдельной кнопки «Объекты» больше нет.
//
// Объединяет прежние TokenDetailsPage и ObjectsPage. connection: "USB" | "NFC".
Page {
    id: page
    objectName: "tokenPage"
    allowedOrientations: Orientation.All

    property var slotId: 0
    property string tokenLabel: ""
    property string serial: ""
    property string tokenModel: ""
    property string manufacturer: ""
    property string connection: ""
    property string firmware: ""
    property string hardware: ""
    property string flags: ""
    property string slotName: ""

    // Текущий вид: "properties" | "objects".
    property string view: "properties"

    // Показ результата в виде «Объекты»: удаление (deleteAttempted) либо
    // создание/импорт (форма вернулась и выставила writeResultShown).
    property bool deleteAttempted: false
    property bool writeResultShown: false
    property bool loginAttempted: false

    // Живая метка. USB — по slotId из TokenWatcher (обновляется по tokensChanged);
    // NFC — из снимка nfcToken (обновляется через setNfcLabel).
    property string curLabel: {
        if (page.connection === "NFC") {
            return (tokenSession.nfcToken.label && tokenSession.nfcToken.label.length > 0)
                   ? tokenSession.nfcToken.label : page.tokenLabel
        }
        var ts = tokenWatcher.tokens
        for (var i = 0; i < ts.length; ++i) {
            if (ts[i].slotId === page.slotId)
                return ts[i].label
        }
        return page.tokenLabel
    }

    // PKCS#11 — основной источник. При opt-in КриптоПро его сертификаты
    // добавляются только для этого же считывателя и только если точного DER
    // среди видимых PKCS#11-объектов нет.
    property var pkcs11ObjectsModel: page.connection === "NFC"
                                     ? tokenSession.nfcObjects : tokenSession.objects
    // По NFC объекты КриптоПро берутся из снимка, снятого в том же поднесении:
    // после отрыва устройства читать CAPI уже нечего.
    property var objectsModel: page.mergeObjects(
                                   page.pkcs11ObjectsModel,
                                   page.connection === "NFC"
                                       ? tokenSession.nfcCryptoProCertificates
                                       : cryptoProSession.certificates,
                                   page.connection === "NFC"
                                       ? tokenSession.nfcCryptoProContainers
                                       : cryptoProSession.containers,
                                   appSettings.cryptoProEnabled,
                                   page.slotName)
    property int objectCount: page.objectsModel.length
    // Чтение ещё идёт: экран уже открыт, но счётчик объектов промежуточный.
    property bool objectsLoading: tokenSession.busy
                                  || (appSettings.cryptoProEnabled && cryptoProSession.busy)

    function normalizedReader(value) {
        return value ? value.toString().trim().toLowerCase().replace(/\s+/g, " ") : ""
    }

    function sameReader(left, right) {
        var a = page.normalizedReader(left)
        var b = page.normalizedReader(right)
        if (a.length === 0 || b.length === 0)
            return false
        if (a === b)
            return true
        // CK_SLOT_INFO у rtPKCS11ECP добавляет к имени PC/SC-ридера номер
        // слота (" ... 00"), которого нет в CAPI FQCN.
        if (a.indexOf(b + " ") === 0 && /^[0-9]{2}$/.test(a.slice(b.length + 1)))
            return true
        return b.indexOf(a + " ") === 0
                && /^[0-9]{2}$/.test(b.slice(a.length + 1))
    }

    function cryptoProObject(certificate) {
        var linkedKeys = []
        if (certificate.privateKeyAvailable) {
            linkedKeys.push({
                keyClass: qsTr("private key"),
                keyType: certificate.algorithm ? certificate.algorithm : "",
                label: certificate.container ? certificate.container : "",
                source: qsTr("CryptoPro CSP")
            })
        }
        return {
            kind: "certificate",
            commonName: certificate.commonName ? certificate.commonName : "",
            issuer: certificate.issuer ? certificate.issuer : "",
            expiry: certificate.notAfter ? certificate.notAfter : "",
            notAfterMs: certificate.notAfterMs ? certificate.notAfterMs : 0,
            expired: certificate.expired ? true : false,
            parsed: (certificate.commonName && certificate.commonName.length > 0)
                    || (certificate.issuer && certificate.issuer.length > 0),
            idHex: "",
            idText: certificate.serial ? certificate.serial : "",
            label: "",
            // Путь контейнера показываем в строке метаданных — там же, где для
            // PKCS#11-сертификатов выводятся CKA_LABEL/CKA_ID, а не в заголовке:
            // в заголовке должен быть Common Name.
            container: certificate.container ? certificate.container : "",
            derB64: certificate.derB64 ? certificate.derB64 : "",
            source: qsTr("CryptoPro CSP"),
            keysKnown: true,
            hasKey: certificate.privateKeyAvailable ? true : false,
            keys: linkedKeys,
            cryptoPro: true
        }
    }

    function cryptoProContainerObject(container) {
        // Путь контейнера — в строке метаданных (место CKA_ID), а не в
        // заголовке. Заголовок контейнера без сертификата — родовое название.
        var path = container.name ? container.name
                                  : (container.uniqueName ? container.uniqueName : "")
        // Уникальное имя показываем отдельной частью, когда оно отличается от
        // отображаемого: режим носителя закодирован именно в нём, и без него две
        // записи об одном устройстве выглядят одинаково.
        var unique = container.uniqueName ? container.uniqueName : ""
        return {
            kind: "key",
            idHex: "",
            idText: path,
            uniqueText: unique === path ? "" : unique,
            label: qsTr("Key container"),
            keyType: container.algorithm ? container.algorithm : "",
            // Контейнер режимов CSP и ФКН показывается своей карточкой: оба
            // ключа лежат в самом контейнере, искать пару не требуется.
            keyClass: qsTr("key pair"),
            containerMode: container.mediaMode ? container.mediaMode : "",
            source: qsTr("CryptoPro CSP"),
            providerType: container.providerType ? container.providerType : 0,
            cryptoPro: true
        }
    }

    // Байты hex-строки в обратном порядке: у ГОСТ открытый ключ в контейнере и
    // в сертификате может отличаться порядком байт (RFC 4491).
    function reversedHex(hex) {
        var out = ""
        for (var i = hex.length - 2; i >= 0; i -= 2)
            out += hex.substr(i, 2)
        return out
    }

    // Контейнер принадлежит уже показанному сертификату, если экспортированный
    // открытый ключ контейнера содержит открытый ключ этого сертификата. Тогда
    // отдельной строкой контейнер не показываем — ключ виден дочерним объектом
    // своего сертификата. Возвращает совпавший открытый ключ или пустую строку.
    function containerBelongsToCertificate(container, publicKeys) {
        var blobs = container.publicKeyBlobs
        if (!blobs || blobs.length === 0 || publicKeys.length === 0)
            return ""
        for (var b = 0; b < blobs.length; ++b) {
            var blob = String(blobs[b]).toLowerCase()
            if (blob.length === 0)
                continue
            for (var k = 0; k < publicKeys.length; ++k) {
                var key = String(publicKeys[k]).toLowerCase()
                if (key.length === 0)
                    continue
                if (blob.indexOf(key) >= 0 || blob.indexOf(page.reversedHex(key)) >= 0)
                    return publicKeys[k]
            }
        }
        return ""
    }

    // Объект, найденный обоими интерфейсами, должен честно об этом сообщать.
    function relabelDualSource(list, bothDer, bothKey) {
        var out = []
        for (var i = 0; i < list.length; ++i) {
            var o = list[i]
            var both = (o.derB64 && bothDer[o.derB64])
                    || (o.publicKeyHex && bothKey[o.publicKeyHex])
            if (!both || o.cryptoPro) {
                out.push(o)
                continue
            }
            var copy = {}
            for (var key in o)
                copy[key] = o[key]
            copy.source = qsTr("PKCS#11 and CryptoPro CSP")
            out.push(copy)
        }
        return out
    }

    // Завершающие нулевые байты не значимы: КриптоПро пишет `CKA_ID` как
    // ASCII(имя контейнера) + 0x00, а имя контейнера этого нуля не содержит.
    function normalizedKeyId(hex) {
        var value = hex ? hex.toString().toLowerCase() : ""
        while (value.length >= 2 && value.substr(value.length - 2, 2) === "00")
            value = value.substr(0, value.length - 2)
        return value
    }

    // Ключевая пара PKCS#11, которая одновременно является контейнером
    // КриптоПро: отдельной строки контейнер не даёт, но его путь и режим
    // носителя переезжают на карточку ключа, а источник становится двойным.
    function keyWithContainer(keyObject, container) {
        var copy = {}
        for (var key in keyObject)
            copy[key] = keyObject[key]
        copy.source = qsTr("PKCS#11 and CryptoPro CSP")
        copy.container = container.name ? container.name
                                        : (container.uniqueName ? container.uniqueName : "")
        copy.containerMode = container.mediaMode ? container.mediaMode : ""
        return copy
    }

    function mergeObjects(pkcs11Objects, cryptoProCertificates,
                          cryptoProContainers, enabled, readerName) {
        var active = []
        var keys = []
        var expired = []
        var visibleDer = {}
        var representedContainers = {}
        // Открытые ключи всех показанных сертификатов — по ним ключевой
        // контейнер КриптоПро связывается со своим сертификатом.
        var shownPublicKeys = []
        // Объекты, найденные и через PKCS#11, и через КриптоПро.
        var bothDer = {}
        var bothKey = {}
        var i
        pkcs11Objects = pkcs11Objects || []
        cryptoProCertificates = cryptoProCertificates || []
        cryptoProContainers = cryptoProContainers || []
        for (i = 0; i < pkcs11Objects.length; ++i) {
            var object = pkcs11Objects[i]
            if (object.kind === "certificate") {
                if (object.derB64 && object.derB64.length > 0)
                    visibleDer[object.derB64] = true
                if (object.publicKeyHex && object.publicKeyHex.length > 0)
                    shownPublicKeys.push(object.publicKeyHex)
                if (object.expired)
                    expired.push(object)
                else
                    active.push(object)
            } else {
                keys.push(object)
            }
        }

        if (enabled) {
            var wantedReader = page.normalizedReader(readerName)
            for (i = 0; i < cryptoProCertificates.length; ++i) {
                var certificate = cryptoProCertificates[i]
                var der = certificate.derB64 ? certificate.derB64 : ""
                if (wantedReader.length === 0
                        || !page.sameReader(certificate.readerName, wantedReader)
                        || der.length === 0)
                    continue
                if (certificate.publicKeyHex && certificate.publicKeyHex.length > 0)
                    shownPublicKeys.push(certificate.publicKeyHex)
                if (visibleDer[der]) {
                    bothDer[der] = true
                    if (certificate.containerKey)
                        representedContainers[certificate.containerKey] = true
                    continue
                }
                visibleDer[der] = true
                if (certificate.containerKey)
                    representedContainers[certificate.containerKey] = true
                var mapped = page.cryptoProObject(certificate)
                if (mapped.expired)
                    expired.push(mapped)
                else
                    active.push(mapped)
            }
            // Ключевые пары PKCS#11 по нормализованному CKA_ID: контейнер
            // режима PKCS#11 — это та же самая пара, и его имя выводится из её
            // CKA_ID (см. docs/OBJECT_MODEL.md). Сравнение строк, носитель при
            // этом не опрашивается.
            var keysById = {}
            for (i = 0; i < keys.length; ++i) {
                var keyId = page.normalizedKeyId(keys[i].idHex)
                if (keyId.length === 0)
                    continue
                if (!keysById[keyId])
                    keysById[keyId] = []
                keysById[keyId].push(i)
            }

            for (i = 0; i < cryptoProContainers.length; ++i) {
                var container = cryptoProContainers[i]
                if (wantedReader.length === 0
                        || !page.sameReader(container.readerName, wantedReader)
                        || (container.containerKey
                            && representedContainers[container.containerKey]))
                    continue
                var boundId = page.normalizedKeyId(container.keyIdHex)
                if (boundId.length > 0 && keysById[boundId]) {
                    var bound = keysById[boundId]
                    for (var b = 0; b < bound.length; ++b)
                        keys[bound[b]] = page.keyWithContainer(keys[bound[b]], container)
                    continue
                }
                var ownerKey = page.containerBelongsToCertificate(container, shownPublicKeys)
                if (ownerKey.length > 0) {
                    bothKey[ownerKey] = true
                    continue
                }
                // Контейнер режима PKCS#11 — это ключевая пара PKCS#11, и её
                // владелец — backend PKCS#11. Своей строки он не получает
                // никогда: если пара ещё не видна (не введён PIN-код), объект
                // просто не показывается — ровно как при выключенном КриптоПро.
                // Иначе список зависел бы от того, включён ли провайдер.
                if (boundId.length > 0)
                    continue
                keys.push(page.cryptoProContainerObject(container))
            }
        }
        active = page.relabelDualSource(active, bothDer, bothKey)
        expired = page.relabelDualSource(expired, bothDer, bothKey)
        return active.concat(keys).concat(expired)
    }

    function certTitle(o) {
        if (o.parsed && o.commonName && o.commonName.length > 0)
            return o.commonName
        if (o.label && o.label.length > 0)
            return o.label
        return ""
    }

    function openPinPad() {
        if (tokenSession.busy)
            return
        var pad = pageStack.push(Qt.resolvedUrl("PinPadPage.qml"), {
            heading: qsTr("User PIN"),
            subtitle: page.curLabel.length > 0 ? page.curLabel : qsTr("Rutoken"),
            acceptText: qsTr("Log in")
        })
        pad.entered.connect(function(pin) {
            page.loginAttempted = true
            tokenSession.login(page.slotId, pin)
        })
    }

    function openObjectLogin() {
        if (tokenSession.busy)
            return
        if (page.connection === "NFC") {
            pageStack.push(Qt.resolvedUrl("NfcConnectPage.qml"), {
                operation: "connect",
                requirePin: true,
                returnToCaller: true
            })
        } else {
            page.openPinPad()
        }
    }

    // Удаление записи долгим нажатием. Сертификат — всегда спрашиваем область.
    // USB — DeleteCertPage; NFC — NfcDeletePage (сбор + одно поднесение). Ключ по
    // USB — сразу, с отсрочкой RemorsePopup.
    function confirmDelete(m) {
        if (!m.idHex || m.idHex.length === 0)
            return
        if (page.connection === "NFC") {
            pageStack.push(Qt.resolvedUrl("NfcDeletePage.qml"), {
                kind: m.kind,
                idHex: m.idHex,
                certName: page.certTitle(m),
                hasKey: m.hasKey ? true : false,
                keysKnown: m.keysKnown ? true : false,
                slotId: page.slotId
            })
            return
        }
        if (m.kind === "certificate") {
            var id = m.idHex
            var dlg = pageStack.push(Qt.resolvedUrl("DeleteCertPage.qml"), {
                certName: page.certTitle(m),
                idHex: id,
                slotId: page.slotId
            })
            dlg.chosen.connect(function(keysToo, noLogin) {
                page.deleteAttempted = true
                if (noLogin)
                    tokenSession.deleteCertPublic(page.slotId, id)
                else
                    tokenSession.deleteObjectsCached(page.slotId, id, keysToo)
            })
        } else {
            remorse.execute(qsTr("Deleting the key"), function() {
                page.deleteAttempted = true
                tokenSession.deleteObjectsCached(page.slotId, m.idHex, true)
            })
        }
    }

    // Сертификаты видны без входа — читаем сразу при открытии (USB). NFC — снимок.
    Component.onCompleted: if (page.connection !== "NFC") tokenSession.preview(page.slotId)

    RemorsePopup { id: remorse }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        // Меню-шторка контекстна виду: «Объекты» → создание объектов;
        // «Свойства» → администрирование токена (смена/разблокировка PIN-кодов, метка).
        PullDownMenu {
            // --- Вид «Объекты» ---
            MenuItem {
                visible: page.view === "objects"
                text: qsTr("Import certificate")
                onClicked: pageStack.push(Qt.resolvedUrl("ImportCertificatePage.qml"), {
                    slotId: page.slotId, connection: page.connection, objectsPage: page
                })
            }
            MenuItem {
                visible: page.view === "objects"
                text: qsTr("Generate key pair")
                onClicked: pageStack.push(Qt.resolvedUrl("GenerateKeyPage.qml"), {
                    slotId: page.slotId, connection: page.connection, objectsPage: page
                })
            }
            // Создание контейнера КриптоПро — при включённом backend'е. По NFC
            // форма собирает данные, а сама операция идёт через мастер
            // поднесения, как генерация и импорт.
            MenuItem {
                visible: page.view === "objects" && appSettings.cryptoProEnabled
                text: qsTr("New CryptoPro container")
                onClicked: pageStack.push(Qt.resolvedUrl("CryptoProContainerPage.qml"), {
                    readerName: page.slotName, deviceLabel: page.curLabel,
                    objectsPage: page, connection: page.connection
                })
            }
            // --- Вид «Свойства»: администрирование ---
            MenuItem {
                visible: page.view === "properties"
                text: qsTr("Change Rutoken label")
                onClicked: pageStack.push(Qt.resolvedUrl("TokenLabelPage.qml"),
                                          { slotId: page.slotId, currentLabel: page.curLabel,
                                            connection: page.connection })
            }
            MenuItem {
                visible: page.view === "properties"
                text: qsTr("Unblock user PIN")
                onClicked: pageStack.push(Qt.resolvedUrl("PinChangePage.qml"),
                                          { slotId: page.slotId, mode: "unblock",
                                            connection: page.connection })
            }
            MenuItem {
                visible: page.view === "properties"
                text: qsTr("Change admin PIN")
                onClicked: pageStack.push(Qt.resolvedUrl("PinChangePage.qml"),
                                          { slotId: page.slotId, mode: "so",
                                            connection: page.connection })
            }
            MenuItem {
                visible: page.view === "properties"
                text: qsTr("Change user PIN")
                onClicked: pageStack.push(Qt.resolvedUrl("PinChangePage.qml"),
                                          { slotId: page.slotId, mode: "user",
                                            connection: page.connection })
            }
        }

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: page.curLabel.length > 0 ? page.curLabel : qsTr("Rutoken")
                description: page.connection.length > 0 ? page.connection : qsTr("device")
            }

            // === Переключатель вида (Свойства | Объекты) ===
            Row {
                id: switcher
                width: parent.width
                height: Theme.itemSizeSmall

                BackgroundItem {
                    id: segProps
                    width: switcher.width / 2
                    height: switcher.height
                    onClicked: page.view = "properties"
                    Label {
                        anchors.centerIn: parent
                        text: qsTr("Properties")
                        color: page.view === "properties" ? Theme.highlightColor
                                                          : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: Math.max(2, Math.round(Theme.paddingSmall / 2))
                        color: Theme.highlightColor
                        opacity: page.view === "properties" ? 1.0 : 0.0
                    }
                }
                BackgroundItem {
                    id: segObjs
                    width: switcher.width / 2
                    height: switcher.height
                    onClicked: page.view = "objects"
                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.paddingSmall

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.objectCount > 0
                                  ? qsTr("Objects · %1").arg(page.objectCount)
                                  : qsTr("Objects")
                            color: page.view === "objects" ? Theme.highlightColor
                                                           : Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        // Пока чтение не закончилось, счётчик может измениться.
                        BusyIndicator {
                            anchors.verticalCenter: parent.verticalCenter
                            running: page.objectsLoading
                            visible: page.objectsLoading
                            size: BusyIndicatorSize.ExtraSmall
                        }
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: Math.max(2, Math.round(Theme.paddingSmall / 2))
                        color: Theme.highlightColor
                        opacity: page.view === "objects" ? 1.0 : 0.0
                    }
                }
            }

            // ===================== ВИД «СВОЙСТВА» =====================
            Column {
                id: propsCol
                visible: page.view === "properties"
                width: parent.width
                spacing: Theme.paddingMedium

                DetailItem {
                    label: qsTr("Serial number")
                    value: page.serial.length > 0 ? page.serial : "—"
                }
                DetailItem {
                    label: qsTr("Model")
                    value: page.tokenModel.length > 0 ? page.tokenModel : "—"
                }
                DetailItem {
                    label: qsTr("Manufacturer")
                    value: page.manufacturer.length > 0 ? page.manufacturer : "—"
                }
                DetailItem {
                    label: qsTr("Firmware / hardware")
                    value: (page.firmware.length > 0 ? page.firmware : "—")
                           + " / " + (page.hardware.length > 0 ? page.hardware : "—")
                }
                DetailItem {
                    label: qsTr("Reader")
                    value: page.slotName.length > 0 ? page.slotName : "—"
                }
                DetailItem {
                    label: qsTr("Flags")
                    value: page.flags.length > 0 ? page.flags : "—"
                }

                // Администрирование токена (смена/разблокировка PIN-кодов, метка) —
                // в меню-шторке сверху (потяните вниз). Для NFC каждая операция
                // соберёт данные и попросит одно поднесение токена.
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Pull down for administration: change or unblock PINs, change the label.")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }

            // ===================== ВИД «ОБЪЕКТЫ» =====================
            Column {
                id: objectsCol
                visible: page.view === "objects"
                width: parent.width
                spacing: Theme.paddingSmall

                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: tokenSession.busy
                    visible: tokenSession.busy
                    size: BusyIndicatorSize.Medium
                }

                // Результат последней операции (удаление/создание/импорт), в т.ч.
                // итог тестовой подписи после генерации.
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    visible: (page.deleteAttempted || page.writeResultShown)
                             && !tokenSession.busy && tokenSession.outcome !== 0
                    text: tokenSession.result
                    color: tokenSession.outcome === 1 ? "#4caf50" : "#f44336"
                    font.pixelSize: Theme.fontSizeSmall
                }

                // Вход расположен только рядом с сертификатами/ключами. USB
                // запоминает PIN; NFC перечитывает снимок за одно поднесение.
                Button {
                    visible: !tokenSession.busy
                             && ((page.connection !== "NFC" && !tokenSession.loggedIn)
                                 || (page.connection === "NFC"
                                     && !tokenSession.nfcAuthenticated))
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Enter PIN to see keys")
                    onClicked: page.openObjectLogin()
                }
                // Успех входа виден по исчезновению кнопки и появлению ключей.
                // Отдельные зелёные статусы и ручной выход здесь не нужны.
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    visible: page.connection !== "NFC" && page.loginAttempted
                             && !tokenSession.busy && tokenSession.outcome === -1
                    text: tokenSession.result
                    color: "#f44336"
                    font.pixelSize: Theme.fontSizeMedium
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: page.objectsModel.length === 0
                    wrapMode: Text.Wrap
                    text: qsTr("No certificates or keys found on the Rutoken")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeMedium
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: page.objectsModel.length > 0
                    wrapMode: Text.Wrap
                    text: qsTr("Press and hold an item to delete it")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: page.objectsModel.length > 0
                    wrapMode: Text.Wrap
                    text: qsTr("Tap a key to create a certificate request (CSR)")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }

                Repeater {
                    model: page.objectsModel

                    delegate: BackgroundItem {
                        width: objectsCol.width
                        height: card.height + Theme.paddingMedium
                        opacity: modelData.kind === "certificate" && modelData.expired
                                 ? 0.45 : 1.0
                        onClicked: {
                            if (modelData.kind === "certificate")
                                pageStack.push(Qt.resolvedUrl("CertificatePage.qml"), {
                                    commonName: modelData.commonName ? modelData.commonName : "",
                                    issuer: modelData.issuer ? modelData.issuer : "",
                                    expiry: modelData.expiry ? modelData.expiry : "",
                                    parsed: modelData.parsed ? modelData.parsed : false,
                                    idText: modelData.idText ? modelData.idText : "",
                                    idHex: modelData.idHex ? modelData.idHex : "",
                                    label: modelData.label ? modelData.label : "",
                                    source: modelData.source ? modelData.source : "",
                                    derB64: modelData.derB64 ? modelData.derB64 : "",
                                    notAfterMs: modelData.notAfterMs ? modelData.notAfterMs : 0,
                                    hasKey: modelData.hasKey ? modelData.hasKey : false,
                                    keysKnown: modelData.keysKnown ? modelData.keysKnown : false,
                                    cryptoPro: modelData.cryptoPro ? true : false,
                                    container: modelData.container ? modelData.container : "",
                                    slotId: page.slotId,
                                    connection: page.connection
                                })
                            else if (modelData.kind === "key" && modelData.cryptoPro
                                     && modelData.idText && modelData.idText.length > 0)
                                // Контейнер КриптоПро: запрос формирует провайдер.
                                pageStack.push(Qt.resolvedUrl("CryptoProCsrPage.qml"), {
                                    container: modelData.idText,
                                    providerType: modelData.providerType
                                                  ? modelData.providerType : 80,
                                    deviceLabel: page.curLabel,
                                    connection: page.connection
                                })
                            else if (modelData.kind === "key"
                                     && modelData.idHex && modelData.idHex.length > 0)
                                pageStack.push(Qt.resolvedUrl("CsrPage.qml"), {
                                    slotId: page.slotId,
                                    idHex: modelData.idHex,
                                    keyName: (modelData.label && modelData.label.length > 0) ? modelData.label : "",
                                    connection: page.connection
                                })
                        }
                        onPressAndHold: {
                            if (!modelData.cryptoPro)
                                page.confirmDelete(modelData)
                        }

                        Column {
                            id: card
                            width: parent.width
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.paddingSmall

                            Row {
                                x: Theme.horizontalPageMargin
                                width: card.width - 2 * Theme.horizontalPageMargin
                                spacing: Theme.paddingMedium

                                Rectangle {
                                    id: kindBadge
                                    anchors.verticalCenter: kindTitle.verticalCenter
                                    width: kindBadgeLabel.width + 2 * Theme.paddingMedium
                                    height: kindBadgeLabel.height + Theme.paddingSmall
                                    radius: Theme.paddingSmall
                                    color: modelData.kind === "certificate"
                                           ? (modelData.expired ? Theme.secondaryColor : "#00695c")
                                           : "#5d4037"
                                    Label {
                                        id: kindBadgeLabel
                                        anchors.centerIn: parent
                                        text: modelData.kind === "certificate" ? qsTr("CERT") : qsTr("KEY")
                                        color: "white"
                                        font.pixelSize: Theme.fontSizeExtraSmall
                                        font.bold: true
                                    }
                                }

                                Label {
                                    id: kindTitle
                                    width: parent.width - kindBadge.width - Theme.paddingMedium
                                    text: modelData.kind === "certificate"
                                          ? page.certTitle(modelData)
                                          : (modelData.label.length > 0 ? modelData.label : "")
                                    color: Theme.highlightColor
                                    font.pixelSize: Theme.fontSizeMedium
                                    truncationMode: TruncationMode.Fade
                                }
                            }

                            Label {
                                x: Theme.horizontalPageMargin
                                width: card.width - 2 * Theme.horizontalPageMargin
                                visible: modelData.kind === "certificate"
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                text: {
                                    var parts = []
                                    if (modelData.kind === "certificate") {
                                        if (modelData.parsed) {
                                            if (modelData.issuer && modelData.issuer.length > 0)
                                                parts.push(qsTr("issuer: %1").arg(modelData.issuer))
                                            if (modelData.expiry && modelData.expiry.length > 0)
                                                parts.push(qsTr("expires: %1").arg(modelData.expiry))
                                        } else if (modelData.idText && modelData.idText.length > 0) {
                                            parts.push(qsTr("ID: %1").arg(modelData.idText))
                                        }
                                        if (modelData.container && modelData.container.length > 0)
                                            parts.push(qsTr("container: %1").arg(modelData.container))
                                        parts.push(modelData.source)
                                    }
                                    return parts.join("  •  ")
                                }
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                            }

                            Label {
                                x: Theme.horizontalPageMargin
                                width: card.width - 2 * Theme.horizontalPageMargin
                                visible: modelData.kind === "key"
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                text: {
                                    var parts = []
                                    if (modelData.kind === "key") {
                                        parts.push(qsTr("ID: %1").arg(modelData.idText && modelData.idText.length > 0 ? modelData.idText : "—"))
                                        if (modelData.uniqueText && modelData.uniqueText.length > 0)
                                            parts.push(qsTr("medium: %1").arg(modelData.uniqueText))
                                        // Ключ, который виден и как контейнер
                                        // КриптоПро: путь и режим носителя не
                                        // теряются при склейке.
                                        if (modelData.container && modelData.container.length > 0)
                                            parts.push(qsTr("container: %1").arg(modelData.container))
                                        if (modelData.containerMode && modelData.containerMode.length > 0)
                                            parts.push(modelData.containerMode)
                                        if (modelData.keyType && modelData.keyType.length > 0)
                                            parts.push(modelData.keyType)
                                        if (modelData.keyClass && modelData.keyClass.length > 0)
                                            parts.push(modelData.keyClass)
                                        parts.push(modelData.source)
                                    }
                                    return parts.join("  •  ")
                                }
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                            }

                            Label {
                                x: Theme.horizontalPageMargin
                                width: card.width - 2 * Theme.horizontalPageMargin
                                visible: modelData.kind === "certificate" && !modelData.keysKnown
                                text: qsTr("keys are shown after PIN login")
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.italic: true
                            }
                            Label {
                                x: Theme.horizontalPageMargin
                                width: card.width - 2 * Theme.horizontalPageMargin
                                visible: modelData.kind === "certificate" && modelData.keysKnown && !modelData.hasKey
                                text: qsTr("certificate without a key (standalone)")
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.italic: true
                            }

                            Repeater {
                                // Дочерние ключи есть и у сертификата, и у
                                // ключевой пары без сертификата.
                                model: modelData.keys ? modelData.keys : []
                                delegate: Row {
                                    x: 2 * Theme.horizontalPageMargin
                                    width: objectsCol.width - 3 * Theme.horizontalPageMargin
                                    spacing: Theme.paddingSmall

                                    Label {
                                        text: "↳"
                                        color: Theme.secondaryColor
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                    Label {
                                        width: parent.width - Theme.paddingLarge
                                        textFormat: Text.PlainText
                                        text: {
                                            var p = [modelData.keyClass]
                                            if (modelData.keyType && modelData.keyType.length > 0)
                                                p.push(modelData.keyType)
                                            if (modelData.label && modelData.label.length > 0)
                                                p.push(modelData.label)
                                            return p.join("  •  ")
                                        }
                                        color: Theme.primaryColor
                                        font.pixelSize: Theme.fontSizeExtraSmall
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }

                            Separator {
                                width: card.width - 2 * Theme.horizontalPageMargin
                                x: Theme.horizontalPageMargin
                                color: Theme.secondaryColor
                                horizontalAlignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
