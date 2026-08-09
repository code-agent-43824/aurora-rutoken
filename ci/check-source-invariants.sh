#!/bin/sh
# Быстрые регрессии для критичных правил v1.1/v1.2 до тяжёлой PSDK-сборки.
set -eu

CMS_SOURCE="src/pkcs11_cms.cpp"
OBJECT_SOURCE="src/pkcs11_objects.cpp"
TOKEN_PAGE="qml/pages/TokenPage.qml"
CERTIFICATE_PAGE="qml/pages/CertificatePage.qml"
CRYPTOPRO_SOURCE="src/cryptoprosession.cpp"
CRYPTOPRO_HEADER="src/cryptopro_capi_minimal.h"
CRYPTOPRO_PAGE="qml/pages/CryptoProPage.qml"
CRYPTOPRO_CERT_PAGE="qml/pages/CryptoProCertificatePage.qml"
CRYPTOPRO_CONTAINER_PAGE="qml/pages/CryptoProContainerPage.qml"
CRYPTOPRO_CSR_PAGE="qml/pages/CryptoProCsrPage.qml"
SETTINGS_PAGE="qml/pages/SettingsPage.qml"
TOKENS_PAGE="qml/pages/TokensPage.qml"
NFC_CONNECT_PAGE="qml/pages/NfcConnectPage.qml"
TOKEN_WATCHER="src/tokenwatcher.cpp"
PKCS11_HEADER="src/pkcs11_minimal.h"
APP_SETTINGS="src/appsettings.cpp"
DIAGNOSTICS_SOURCE="src/diagnostics.cpp"
DESKTOP="ru.codeagent43824.rutokentestapp.desktop"
SPEC="rpm/ru.codeagent43824.rutokentestapp.spec"

grep -Fq \
    'const CK_ULONG flags = detached ? PKCS7_DETACHED_SIGNATURE : 0UL;' \
    "$CMS_SOURCE"
if grep -Eq '^[[:space:]]*const CK_ULONG USE_HARDWARE_HASH' "$CMS_SOURCE"; then
    echo "CMS signing must not enable the hardware-hash flag" >&2
    exit 1
fi

grep -Fq 'QDateTime::currentDateTimeUtc() > notAfter.toUTC()' "$CMS_SOURCE"
grep -Fq 'cert.insert(QStringLiteral("expired"), expired);' "$OBJECT_SOURCE"
grep -Fq 'out.append(activeCertificates);' "$OBJECT_SOURCE"
grep -Fq 'out.append(expiredCertificates);' "$OBJECT_SOURCE"

grep -Fq 'opacity: modelData.kind === "certificate" && modelData.expired' "$TOKEN_PAGE"
grep -Fq 'notAfterMs: modelData.notAfterMs ? modelData.notAfterMs : 0' "$TOKEN_PAGE"
grep -Fq 'visible: !page.expired && page.idHex.length > 0' "$CERTIFICATE_PAGE"

for SYMBOL in \
    CryptEnumProvidersA \
    CryptAcquireContextA \
    CryptGetProvParam \
    CertOpenSystemStoreA \
    CertEnumCertificatesInStore \
    CertGetCertificateContextProperty \
    CertFreeCertificateContext \
    CryptAcquireCertificatePrivateKey; do
    grep -Fq "\"$SYMBOL\"" "$CRYPTOPRO_SOURCE"
done
grep -Fq \
    'QStringLiteral("/usr/lib/3rdparty/ru.cryptopro.csp/lib/libcapi20.so")' \
    "$CRYPTOPRO_SOURCE"
grep -Fq \
    'Permissions=NFC;UserDirs;ru.cryptopro.gui@ru.cryptopro.csp' \
    "$DESKTOP"
grep -Fq 'CryptVerifyContext | capi::CryptSilent' "$CRYPTOPRO_SOURCE"
grep -Fq 'CryptAcquireSilentFlag | capi::CryptAcquireCompareKeyFlag' "$CRYPTOPRO_SOURCE"
grep -Fq 'QCryptographicHash::Sha256' "$CRYPTOPRO_SOURCE"
grep -Fq 'exactDuplicateCount' "$CRYPTOPRO_SOURCE"
grep -Fq 'containerCertificateCount' "$CRYPTOPRO_SOURCE"
grep -Fq 'metadataConflict' "$CRYPTOPRO_SOURCE"
grep -Fq 'typedef wchar_t WideChar;' "$CRYPTOPRO_HEADER"
grep -Fq 'QCoreApplication::applicationFilePath()' "$CRYPTOPRO_SOURCE"
grep -Fq 'QStringLiteral("--cryptopro-scan-helper")' "$CRYPTOPRO_SOURCE"
grep -Fq 'RUTOKEN_CRYPTOPRO_JSON:' "$CRYPTOPRO_SOURCE"
grep -Fq 'const int MaxProviders = 128;' "$CRYPTOPRO_SOURCE"
grep -Fq 'const int MaxContainersPerProvider = 512;' "$CRYPTOPRO_SOURCE"
grep -Fq 'const int MaxCertificates = 4096;' "$CRYPTOPRO_SOURCE"
grep -Fq 'const int MaxHelperOutputBytes = 4 * 1024 * 1024;' "$CRYPTOPRO_SOURCE"
grep -Fq 'physicalContainerKey' "$CRYPTOPRO_SOURCE"
grep -Fq 'logicalContainerByKey' "$CRYPTOPRO_SOURCE"
grep -Fq 'readerNameFromFqcn' "$CRYPTOPRO_SOURCE"
grep -Fq 'row.insert(QStringLiteral("derB64")' "$CRYPTOPRO_SOURCE"
grep -Fq 'status === PageStatus.Active' "$CRYPTOPRO_PAGE"
if grep -Fq 'cryptoProSession.refresh()' "$TOKEN_PAGE"; then
    echo "CryptoPro scan must start only after its page becomes active" >&2
    exit 1
fi

grep -Fq 'C_WaitForSlotEvent(0, &slot, nullptr)' "$TOKEN_WATCHER"
grep -Fq 'QStringLiteral("--pkcs11-slot-event-helper")' "$TOKEN_WATCHER"
grep -Fq 'RUTOKEN_SLOT_EVENT_READY' "$TOKEN_WATCHER"
grep -Fq 'CK_C_WaitForSlotEvent C_WaitForSlotEvent; // 68' "$PKCS11_HEADER"
if grep -Eq 'kPollInterval|setInterval\(|QTimer::timeout' "$TOKEN_WATCHER"; then
    echo "TokenWatcher must use C_WaitForSlotEvent, not timer polling" >&2
    exit 1
fi

grep -Fq 'features/cryptoProEnabled' "$APP_SETTINGS"
grep -Fq 'false).toBool()' "$APP_SETTINGS"
grep -Fq 'text: qsTr("Use CryptoPro CSP")' "$SETTINGS_PAGE"
grep -Fq 'checked: appSettings.cryptoProEnabled' "$SETTINGS_PAGE"
grep -Fq 'text: qsTr("Settings")' "$TOKENS_PAGE"
if grep -Fq 'pageStack.push(Qt.resolvedUrl("CryptoProPage.qml"))' "$TOKENS_PAGE"; then
    echo "The start menu must open Settings, not a separate CryptoPro page" >&2
    exit 1
fi
grep -Fq 'if (!m_enabled)' "$CRYPTOPRO_SOURCE"
grep -Fq 'probeCryptoProLibraries' "$DIAGNOSTICS_SOURCE"
grep -Fq 'if (includeCryptoPro)' "$DIAGNOSTICS_SOURCE"
grep -Fq 'page.mergeObjects(' "$TOKEN_PAGE"
grep -Fq 'visibleDer[object.derB64] = true' "$TOKEN_PAGE"
grep -Fq '!page.sameReader(certificate.readerName, wantedReader)' "$TOKEN_PAGE"
grep -Fq 'cryptoProSession.containers' "$TOKEN_PAGE"
grep -Fq 'representedContainers[certificate.containerKey] = true' "$TOKEN_PAGE"
grep -Fq 'page.cryptoProContainerObject(container)' "$TOKEN_PAGE"
grep -Fq 'row.insert(QStringLiteral("containerKey"), physicalKey);' "$CRYPTOPRO_SOURCE"
grep -Fq 'QStringLiteral("/proc/self/maps")' "$CRYPTOPRO_SOURCE"
grep -Fq 'loadedCryptoProLibraries(library.fileName())' "$CRYPTOPRO_SOURCE"
grep -Fq 'diagnostics.setCryptoProLibraries(cryptoProSession.loadedLibraries())' src/main.cpp
grep -Fq 'if (!modelData.cryptoPro)' "$TOKEN_PAGE"

# Инвариант адаптера КриптоПро. С v1.3 разрешена запись (создание контейнера и
# ключевой пары), поэтому запрет точечный: остаются запрещёнными сторонние
# утилиты и shell, смешивание с PKCS#11, запись в хранилище сертификатов и
# импорт чужого ключа. CryptDestroyKey — освобождение дескриптора в памяти.
if grep -Eiq 'pkcs11|certmgr|cryptcp|/bin/(sh|bash)|C_Set|CertSet|CertAdd|CertDelete|CryptImportKey|CryptSetKeyParam' \
        "$CRYPTOPRO_SOURCE" "$CRYPTOPRO_HEADER"; then
    echo "CryptoPro adapter must stay internal-helper, CapiLite-only, without store writes" >&2
    exit 1
fi

# --- v1.3: запись через КриптоПро ---
# Запись живёт в отдельном одноразовом helper-режиме.
grep -Fq 'QStringLiteral("--cryptopro-write-helper")' "$CRYPTOPRO_SOURCE"
grep -Fq 'CryptoProSession::runWriteHelper()' src/main.cpp
# PIN-код передаётся ТОЛЬКО через stdin: аргументы процесса видны в системе.
grep -Fq 'm_createHelper.setArguments(QStringList(QStringLiteral("--cryptopro-write-helper")))' \
    "$CRYPTOPRO_SOURCE"
grep -Fq 'm_createHelper.write(m_createPayload);' "$CRYPTOPRO_SOURCE"
if grep -Eq 'setArguments\(.*(pin|Pin)' "$CRYPTOPRO_SOURCE"; then
    echo "The PIN must never be passed as a process argument" >&2
    exit 1
fi
# PKCS#10 кодирует и подписывает сам провайдер: мы не разбираем PUBLICKEYBLOB и
# не переставляем байты подписи ГОСТ.
grep -Fq 'api.signAndEncode(provider, capi::AtSignature, capi::X509AsnEncoding,' "$CRYPTOPRO_SOURCE"
grep -Fq 'capi::CertRequestToBeSigned' "$CRYPTOPRO_SOURCE"
grep -Fq 'api.exportPublicKeyInfo(provider, capi::AtSignature,' "$CRYPTOPRO_SOURCE"
# Один физический ключ не должен показываться двумя контейнерами: собственное
# имя и внутренний алиас PKCS#11 склеиваются по экспортированному открытому ключу.
grep -Fq 'QHash<QString, int> containerByKey;' "$CRYPTOPRO_SOURCE"
# Представление ключа PKCS#11 глазами CSP (`pkcs_key_…`) не показывается как
# контейнер КриптоПро: владелец такого объекта — backend PKCS#11. Отсев идёт до
# открытия контейнера, поэтому он же экономит самые дорогие обращения.
grep -Fq 'bool isProviderKeyAliasContainer(const Container &container)' "$CRYPTOPRO_SOURCE"
grep -Fq 'isRutokenContainer(container) && !isProviderKeyAliasContainer(container)' "$CRYPTOPRO_SOURCE"
grep -Fq 'QStringLiteral("pkcs_key")' "$CRYPTOPRO_SOURCE"
grep -Fq 'mergedInto.insert(' "$CRYPTOPRO_SOURCE"
# Ключевая пара создаётся неэкспортируемой (без CRYPT_EXPORTABLE).
grep -Fq 'api.genKey(provider, capi::AtSignature, 0, &key)' "$CRYPTOPRO_SOURCE"
if grep -Fq 'CryptExportable' "$CRYPTOPRO_SOURCE"; then
    echo "Generated CryptoPro keys must not be exportable" >&2
    exit 1
fi
# Удаление контейнера разрешено ТОЛЬКО как откат собственного создания и живёт
# в одной выделенной функции; создание — тоже ровно в одном месте.
grep -Fq 'bool rollbackCreatedContainer(' "$CRYPTOPRO_SOURCE"
DELETE_USES=$(grep -c 'capi::CryptDeleteKeyset' "$CRYPTOPRO_SOURCE")
NEW_USES=$(grep -c 'capi::CryptNewKeyset' "$CRYPTOPRO_SOURCE")
if [ "$DELETE_USES" -ne 1 ] || [ "$NEW_USES" -ne 1 ]; then
    echo "Container creation and rollback deletion must each exist in exactly one place" >&2
    exit 1
fi

# Сертификат должен читаться ИЗНУТРИ контейнера: перечисление хранилища «MY»
# возвращает только установленные сертификаты, которых у нас нет.
grep -Fq 'capi::KpCertificate' "$CRYPTOPRO_SOURCE"
grep -Fq 'api.getUserKey(provider, keySpec, &key)' "$CRYPTOPRO_SOURCE"
grep -Fq 'readContainerCertificates(api, container)' "$CRYPTOPRO_SOURCE"
# Открытие контейнера обязано быть тихим, иначе CSP поднимет системный запрос
# PIN-кода в ограниченном helper-процессе.
grep -Fq 'container.providerType, capi::CryptSilent)' "$CRYPTOPRO_SOURCE"
# Дубликат по точному DER не плодим.
grep -Fq 'knownCertificateHashes.contains(sha256)' "$CRYPTOPRO_SOURCE"
# Заголовок карточки — Common Name; путь контейнера — в строке метаданных.
grep -Fq 'qsTr("container: %1").arg(modelData.container)' "$TOKEN_PAGE"
grep -Fq 'label: qsTr("Key container")' "$TOKEN_PAGE"
# Ключевой контейнер не показывается отдельно, если его открытый ключ совпал с
# ключом уже показанного сертификата: ключ виден дочерним объектом сертификата.
grep -Fq 'capi::PublicKeyBlob' "$CRYPTOPRO_SOURCE"
grep -Fq 'rawPublicKeyFromCertificate(der)' "$CRYPTOPRO_SOURCE"
grep -Fq 'page.containerBelongsToCertificate(container, shownPublicKeys)' "$TOKEN_PAGE"
grep -Fq 'publicKeyFromCertificate(der).toHex()' src/pkcs11_objects.cpp
# Путь контейнера виден и на карточке сертификата, и версия CSP — в диагностике.
grep -Fq 'label: qsTr("Container")' "$CERTIFICATE_PAGE"
grep -Fq 'capi::PpVersion' "$CRYPTOPRO_SOURCE"
grep -Fq 'diagnostics.setCryptoProVersion(cryptoProSession.cspVersion());' src/main.cpp
# КриптоПро на NFC: чтение идёт в том же поднесении, результат — снимком.
grep -Fq 'tokenSession.setNfcCryptoPro(cryptoProSession.certificates,' "$NFC_CONNECT_PAGE"
# Проход CAPI запускается только при включённом backend'е и только там, где он
# нужен: подключение и УСПЕШНОЕ создание контейнера. Неудачная запись ничего не
# изменила — перечитывать носитель незачем, по NFC это лишние секунды.
grep -Fq 'if (!appSettings.cryptoProEnabled)' "$NFC_CONNECT_PAGE"
grep -Fq 'return page.operation === "connect"' "$NFC_CONNECT_PAGE"
grep -Fq '&& cryptoProSession.createOutcome === 1)' "$NFC_CONNECT_PAGE"
# NFC-считыватель называется ifd-nfcd-handler, поэтому без признака NFC фильтр
# отбрасывал бы все контейнеры поднесённого устройства.
grep -Fq 'haystack.contains(QStringLiteral("nfc"))' "$CRYPTOPRO_SOURCE"
# Автопроход не трогает NFC: там каналом распоряжается мастер поднесения,
# и мастер обязан дождаться ИМЕННО своего прохода.
grep -Fq 'card.value(QStringLiteral("connection")).toString()' "$CRYPTOPRO_SOURCE"
grep -Fq 'cryptoProSession.scanSerial === page.cryptoProSerial' "$NFC_CONNECT_PAGE"
grep -Fq 'if (tokenSession.busy || cryptoProSession.busy)' "$NFC_CONNECT_PAGE"
# Шапка экрана сертификата строится из ФАКТИЧЕСКОГО источника: объект может быть
# виден обоими интерфейсами сразу.
grep -Fq 'qsTr("Certificate — via %1").arg(page.source)' "$CERTIFICATE_PAGE"
if grep -Fq 'qsTr("Certificate — via PKCS#11")' "$CERTIFICATE_PAGE"; then
    echo "The certificate header must follow the actual source, not the backend flag" >&2
    exit 1
fi
# Пока идёт чтение, у счётчика объектов виден индикатор прогресса.
grep -Fq 'running: page.objectsLoading' "$TOKEN_PAGE"
grep -Fq 'tokenSession.nfcCryptoProCertificates' "$TOKEN_PAGE"
# Набор ГОСТ-провайдеров задаётся пользователем и одинаково управляет чтением и
# созданием: создать контейнер провайдером, которым мы не читаем, нельзя —
# приложение сделало бы объект, которого само не покажет.
grep -Fq "QList<int> AppSettings::knownProviderTypes()" "$APP_SETTINGS"
grep -Fq 'cryptoProSession.setProviderTypes(appSettings.cryptoProProviderTypeList());' src/main.cpp
grep -Fq 'AppSettings::cryptoProProviderTypesChanged' src/main.cpp
grep -Fq 'if (!m_providerTypes.contains(providerType))' "$CRYPTOPRO_SOURCE"
grep -Fq 'allowedProviderTypes.contains(' "$CRYPTOPRO_SOURCE"
# Пустой набор недопустим: включённый КриптоПро, который ничего не читает, —
# это не состояние, а ловушка. Последний включённый провайдер не выключается.
grep -Fq "if (!enabled && m_providerTypes.size() == 1)" "$APP_SETTINGS"
grep -Fq 'allowedProviderTypes.append(static_cast<int>(capi::ProvGost2012_256));' \
    "$CRYPTOPRO_SOURCE"
# Выключенный провайдер остаётся видимым: и в диагностике, и в форме создания.
grep -Fq 'providerRow.insert(QStringLiteral("enabled"), allowed);' "$CRYPTOPRO_SOURCE"
grep -Fq "enabled: page.providerEnabled(80)" "$CRYPTOPRO_CONTAINER_PAGE"
grep -Fq 'opacity: enabled ? 1.0 : 0.4' "$CRYPTOPRO_CONTAINER_PAGE"
# Предупреждение о цене нескольких провайдеров стоит рядом с самим выбором.
grep -Fq 'especially over NFC' "$SETTINGS_PAGE"

# Режим носителя (ФКН / активный токен / CSP) закодирован в уникальном имени и
# показывается в карточке: без него две записи об одном устройстве неотличимы.
grep -Fq 'QString containerMediaMode(const Container &container)' "$CRYPTOPRO_SOURCE"
grep -Fq 'row.insert(QStringLiteral("mediaMode"), containerMediaMode(container));' "$CRYPTOPRO_SOURCE"
grep -Fq 'qsTr("medium: %1").arg(modelData.uniqueText)' "$TOKEN_PAGE"
# Контейнер режима PKCS#11 — это та же ключевая пара: сопоставление идёт по
# CKA_ID, выведенному ИЗ ИМЕНИ контейнера, без открытия контейнера и без PIN.
# Алгоритм и замеры, на которых он стоит, — docs/OBJECT_MODEL.md.
grep -Fq 'QString containerKeyIdHex(const Container &container)' "$CRYPTOPRO_SOURCE"
grep -Fq 'row.insert(QStringLiteral("keyIdHex"),' "$CRYPTOPRO_SOURCE"
grep -Fq 'function normalizedKeyId(hex)' "$TOKEN_PAGE"
grep -Fq 'keys[bound[b]] = page.keyWithContainer(keys[bound[b]], container)' "$TOKEN_PAGE"
if [ ! -f docs/OBJECT_MODEL.md ]; then
    echo "The object matching algorithm must stay documented in docs/OBJECT_MODEL.md" >&2
    exit 1
fi

# Режим контейнера задаётся ВЫБОРОМ СЧИТЫВАТЕЛЯ, поэтому список считывателей
# читается с устройства через PP_ENUMREADERS, а не зашивается в код: выдуманное
# имя создало бы контейнер не там, где ожидает пользователь.
grep -Fq 'QVariantList enumerateReaders(const Api &api, capi::CryptProv provider, bool media)' "$CRYPTOPRO_SOURCE"
grep -Fq 'capi::PpEnumReaders' "$CRYPTOPRO_SOURCE"
grep -Fq 'static const Dword PpEnumReaders = 114;' "$CRYPTOPRO_HEADER"
grep -Fq 'capi::CryptMedia' "$CRYPTOPRO_SOURCE"
grep -Fq 'model: page.readerOptions()' "$CRYPTOPRO_CONTAINER_PAGE"
grep -Fq 'model: page.modeOptions()' "$CRYPTOPRO_CONTAINER_PAGE"
grep -Fq 'cryptoProSession.createContainer(page.targetNick(),' "$CRYPTOPRO_CONTAINER_PAGE"
if grep -Eq 'QStringLiteral\("Rutoken FKC"\)|QStringLiteral\("HDIMAGE"\)' "$CRYPTOPRO_SOURCE"; then
    echo "Reader names must be read from the device, never hardcoded" >&2
    exit 1
fi

# --- v1.3, этап 3: запись через КриптоПро по NFC ---
# Обе операции идут через тот же мастер поднесения, что и запись PKCS#11.
grep -Fq 'page.operation === "cpcontainer" || page.operation === "cpcsr"' "$NFC_CONNECT_PAGE"
grep -Fq 'operation: "cpcontainer"' "$CRYPTOPRO_CONTAINER_PAGE"
grep -Fq 'operation: "cpcsr"' "$CRYPTOPRO_CSR_PAGE"
# Канал PC/SC один: пока по нему идёт чужой проход, запись не начинается.
grep -Fq 'cryptoProSession.busy || cryptoProSession.createBusy' "$NFC_CONNECT_PAGE"
# Состояние операции КриптоПро не берётся у PKCS#11: у него свой busy/outcome,
# а прошлый outcome tokenSession завершил бы шаг досрочно.
grep -Fq 'if (page.isCryptoProWrite())' "$NFC_CONNECT_PAGE"
grep -Fq 'text: page.opResult()' "$NFC_CONNECT_PAGE"
if grep -Fq 'text: tokenSession.result' "$NFC_CONNECT_PAGE"; then
    echo "The NFC result must follow the backend that ran the operation" >&2
    exit 1
fi

# Лишних CAPI-проходов быть не должно: решение принимает syncWithTokens.
grep -Fq 'cryptoProSession.syncWithTokens(tokenWatcher.tokens());' src/main.cpp
grep -Fq 'if (m_syncedOnce && readers == m_scannedReaders)' "$CRYPTOPRO_SOURCE"
if grep -Fq 'cryptoProSession.refresh();' src/main.cpp; then
    echo "Token changes must go through syncWithTokens, not an unconditional scan" >&2
    exit 1
fi
# Двойной источник и единственная строка версии в диагностике.
grep -Fq 'qsTr("PKCS#11 and CryptoPro CSP")' "$TOKEN_PAGE"
grep -Fq 'rowId != QStringLiteral("cryptoprover")' src/diagnostics.cpp
if grep -Fq 'var label = container.name ? container.name' "$TOKEN_PAGE"; then
    echo "Container path must not be the card title" >&2
    exit 1
fi
if grep -Eiq '^(Requires|BuildRequires):.*(cprocsp|cryptopro)' "$SPEC"; then
    echo "CryptoPro CSP must remain an optional external runtime" >&2
    exit 1
fi

grep -Fq 'model: cryptoProSession.containers' "$CRYPTOPRO_PAGE"
grep -Fq 'model: cryptoProSession.certificates' "$CRYPTOPRO_PAGE"
grep -Fq 'certificate.sha256' "$CRYPTOPRO_CERT_PAGE"
grep -Fq 'This screen does not change certificates or containers' "$CRYPTOPRO_CERT_PAGE"

echo "Source invariants verified: v1.1 CMS/expiry and v1.2 optional read-only CapiLite"
