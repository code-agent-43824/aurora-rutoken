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
grep -Fq 'QStringLiteral("--cryptopro-create-helper")' "$CRYPTOPRO_SOURCE"
grep -Fq 'CryptoProSession::runCreateHelper()' src/main.cpp
# PIN-код передаётся ТОЛЬКО через stdin: аргументы процесса видны в системе.
grep -Fq 'm_createHelper.setArguments(QStringList(QStringLiteral("--cryptopro-create-helper")))' \
    "$CRYPTOPRO_SOURCE"
grep -Fq 'm_createHelper.write(m_createPayload);' "$CRYPTOPRO_SOURCE"
if grep -Eq 'setArguments\(.*(pin|Pin)' "$CRYPTOPRO_SOURCE"; then
    echo "The PIN must never be passed as a process argument" >&2
    exit 1
fi
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
grep -Fq 'page.operation === "connect" && appSettings.cryptoProEnabled' "$NFC_CONNECT_PAGE"
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
