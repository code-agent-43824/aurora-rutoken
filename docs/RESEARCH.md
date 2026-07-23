# Исследование: Рутокен ЭЦП 3.0 на ОС Аврора

Дата: 2026-07-19. Статус: этап 0 (исследование) завершён. Выводы этого документа легли в основу [PLAN.md](../PLAN.md).

## Цель проекта

Тестовое приложение для ОС Аврора, работающее с токенами **Рутокен ЭЦП 3.0** по двум интерфейсам:

- **USB** (контактный);
- **NFC** (бесконтактный, для моделей Рутокен ЭЦП 3.0 NFC).

Ориентировочный функционал (уточняется в PLAN.md): обнаружение токена, информация о нём, ввод PIN, просмотр объектов, генерация ключевой пары ГОСТ, подпись и проверка тестовых данных.

## 1. Где лежат исходники примеров для Авроры

«Открытая мобильная платформа» (ОМП, разработчик ОС Аврора) перенесла свои open-source-проекты на московскую платформу **Мос.Хаб** — https://hub.mos.ru (это и есть «МосХаб»; GitLab-совместимая платформа). Подтверждение: [новость ОМП](https://www.omp.ru/news1/tpost/9psx1zl3m1-open-source-proekti-dlya-os-avrora-stali), [новость mos.ru](https://www.mos.ru/news/item/161601073/).

Головная группа: **https://hub.mos.ru/auroraos** (владелец — ООО «Открытая мобильная платформа», group id 208720).

Подгруппы группы `auroraos`:

| Подгруппа | Путь | Что внутри |
|---|---|---|
| Demos | `auroraos/demos` | Небольшие демо отдельных технологий (~48 проектов) |
| Examples | `auroraos/examples` | Полнофункциональные приложения — «лучшие практики» |
| Examples Extra | `auroraos/examples-extra` | Примеры с тяжёлыми зависимостями (LLM Runner, TTS/STT и др.) |
| Flutter | `auroraos/flutter` | Flutter SDK для Авроры + плагины сообщества |
| Qt | `auroraos/qt` | Qt5/Qt6-библиотеки, инструменты кросс-сборки |
| Образование | `auroraos/edu` | Курсы: «Прикладная разработка на Qt», «Разработка плагинов Flutter» |
| Kotlin Multiplatform | `auroraos/kotlin-multiplatform` | Compose Multiplatform для Авроры |
| Applications | `auroraos/apps` | Портированные приложения (TgChat/tdesktop и др.) |

Каталог примеров с описаниями: https://developer.auroraos.ru/demos и https://developer.auroraos.ru/doc/software_development/examples

Клонирование: `git clone https://hub.mos.ru/auroraos/demos/NfcUseCases.git`

### Ключевые для нас репозитории

| Репозиторий | URL | Зачем нам |
|---|---|---|
| **Application Template** | https://hub.mos.ru/auroraos/demos/ApplicationTemplate | Эталонная структура нативного приложения: qmake `.pro`, `rpm/*.spec`, `.desktop`, `src/`, `qml/` (страницы, cover, иконки). BSD-3-Clause |
| **NFC Use Cases** | https://hub.mos.ru/auroraos/demos/NfcUseCases | **Главный референс.** Работа с NFC двумя путями: (1) **pcsc-lite** — обнаружение NFC-меток/карт как PC/SC-ридера; (2) **nfcd через D-Bus** с QML-обвязкой. qmake, BSD-3-Clause |
| **USB Use Cases** | https://hub.mos.ru/auroraos/demos/UsbUseCases | USB API Авроры, сборка и использование libusb (для диагностики; сам токен идёт через pcscd/CCID) |
| Key Store | https://hub.mos.ru/auroraos/demos/KeyStore | QCA Keystore API (общие подходы к крипто-UI) |
| Cryptographic QCA | https://hub.mos.ru/auroraos/demos/CryptographicQca | Криптография через QCA API |
| UI Component Gallery | https://hub.mos.ru/auroraos/demos/UIComponentGallery | Галерея UI-компонентов Авроры, лучшие практики |
| Flutter SDK | https://hub.mos.ru/auroraos/flutter/flutter | Flutter для Авроры (оценивали как альтернативу) |
| nfc_manager (Flutter) | https://hub.mos.ru/auroraos/flutter/flutter-community-plugins/nfc_manager | NFC-плагин Flutter для Авроры (PC/SC-уровня не даёт) |

Примечания к примерам:

- **ApplicationTemplate**: qmake-проект `ru.auroraos.ApplicationTemplate.pro`; структура `src/` (C++, `main.cpp`), `qml/` (pages, cover, icons), `icons/`, `rpm/*.spec`, `.desktop`; RPM-пакетирование; в актуальных версиях — QML-компоненты Авроры (не `Sailfish.Silica`).
- **NfcUseCases**: qmake-проект `ru.auroraos.NfcUseCases.pro`; модуль на pcsc-lite «обнаруживает подключение NFC-меток и выводит базовую информацию о них»; модуль nfcd — D-Bus-интерфейсы демона `nfcd` с QML-обёртками. Это подтверждает: **бесконтактные карты на Авроре доступны через PC/SC**, тем же интерфейсом, что и USB-токены.

## 2. Как Рутокен работает на ОС Аврора

Подтверждено источниками (список в конце):

- Рутокен ЭЦП 3.0 (включая NFC-модели) **официально поддерживает ОС Аврора** (версии 4 и выше). В каталоге приложений Авроры есть приложение «Рутокен» от компании «Актив»: https://auroraos.ru/applications/rutoken — подпись формируется «на борту» токена, ключ не покидает устройство.
- Библиотека PKCS#11 **rtPKCS11ECP** имеет **официальные сборки для Авроры: RPM ARM32 и ARM64**, текущая версия **2.19.0.0** (17.04.2026). Поддержка Авроры появилась в **2.17.1.0** (заявлены Аврора 4 и 5; архитектуры x86_64, ARM64, ARMv7). Скачивание: https://www.rutoken.ru/support/download/pkcs/ (файлы отдаются с download.rutoken.ru).
- Устройства семейства Рутокен ЭЦП — **CCID-совместимые**: на Linux (и Авроре) USB-подключение обслуживает стандартный стек **pcsc-lite**: демон `pcscd` + CCID ifd-handler, отдельные драйверы не нужны.
- **NFC**: NFC-стеком Авроры управляет демон **`nfcd`** (наследие Sailfish OS). Бесконтактная карта предоставляется приложениям **через тот же PC/SC** — NFC-ридер выглядит как ещё один ридер pcscd (NFC-handler играет ту же роль, что CCID ifd-handler для USB). Демо NfcUseCases это подтверждает (обнаружение NFC-меток через pcsc-lite).

Итоговая схема стека:

```
QML UI (компоненты Авроры)
        │
C++/Qt слой приложения
        │  вызовы C_* (PKCS#11)
librtpkcs11ecp.so  (PKCS#11 v2.20 + российский профиль; ГОСТ и RSA)
        │
libpcsclite ──► pcscd (PC/SC-демон)
        │                     │
  CCID ifd-handler      NFC-handler (стек nfcd)
        │                     │
Рутокен ЭЦП 3.0 (USB)   Рутокен ЭЦП 3.0 NFC
```

Криптография выполняется на борту токена: ГОСТ Р 34.10-2012, ГОСТ Р 34.11-2012, ГОСТ 28147-89, ГОСТ Р 34.12/34.13-2015(2018), а также RSA. Ключи неизвлекаемые.

Полезные факты:

- PIN-коды по умолчанию: пользователь `12345678`, администратор `87654321` (менять при первом использовании).
- Рутокен ЭЦП **Bluetooth** на Авроре **не поддерживается** (нет драйвера) — подтверждено на форуме Рутокен (topic 3779). Актуальный бесконтактный путь — NFC.
- КриптоПро CSP на Авроре **не** умеет работать поверх rtpkcs11ecp (PKCS#11-провайдер) — для нас неважно: работаем с PKCS#11 напрямую, без CSP.

## 3. Rutoken SDK и документация

- Комплект разработчика: https://www.rutoken.ru/developers/sdk/ — PKCS#11-библиотека, примеры кода (включая мобильные под Android/iOS/Аврору/Astra), демо-сервисы подписи, утилиты `pkcs11-tool` (управление токеном из консоли) и `pkcs11-spy` (отладка вызовов PKCS#11).
- Центр загрузки PKCS#11: https://www.rutoken.ru/support/download/pkcs/ — RPM для Авроры ARM32/ARM64; прямые ссылки вида `https://download.rutoken.ru/Rutoken/PKCS11Lib/<версия>/...`.
- Портал документации: https://dev.rutoken.ru
  - [Использование библиотек rtPKCS11 и rtPKCS11ECP](https://dev.rutoken.ru/pages/viewpage.action?pageId=3178509)
  - [Встраивание устройств Рутокен через PKCS#11](https://dev.rutoken.ru/pages/viewpage.action?pageId=13795364)
  - [Отладка приложений, использующих PKCS#11](https://dev.rutoken.ru/pages/viewpage.action?pageId=19496963)
  - [Начало работы со смарт-картой Рутокен ЭЦП 3.0 NFC](https://dev.rutoken.ru/pages/viewpage.action?pageId=78479413)
- Форум техподдержки (отвечают разработчики Актива): https://forum.rutoken.ru

## 4. Выбор фреймворка: нативный Qt vs Flutter

**Решение: нативный Qt/C++ + QML.**

| Критерий | Qt (нативный) | Flutter |
|---|---|---|
| Доступ к PKCS#11 (C API) | Напрямую: `dlopen("librtpkcs11ecp.so")` + `C_GetFunctionList` | Нужен собственный мост (FFI/platform channel) под Аврору |
| Доступ к PC/SC и nfcd | Есть официальный пример NfcUseCases на C++ | Готового плагина нет; `nfc_manager` не даёт PC/SC-уровень |
| Примеры Рутокен SDK | C/C++ | Под Аврору отсутствуют |
| Каркас приложения | ApplicationTemplate готов | Есть шаблоны, но крипто-мост всё равно писать на C++ |
| Кроссплатформенность | Не требуется (целевая ОС одна) | Преимущество не востребовано |

Flutter не отвергается навсегда: если позже понадобится Flutter-UI, мост к librtpkcs11ecp всё равно пишется на C++, и эта работа переиспользуема. Но для тестового приложения нативный Qt — кратчайший и проверенный официальными примерами путь.

## 5. Эскиз функциональности тестового приложения

1. Список PC/SC-ридеров и PKCS#11-слотов (USB- и NFC-ридеры различимы по именам слотов).
2. Информация о токене: `C_GetSlotInfo` / `C_GetTokenInfo` (модель, серийный номер, память).
3. Отслеживание подключения/отключения токена: `C_WaitForSlotEvent` (в отдельном потоке) или опрос.
4. Логин по PIN: `C_Login` / `C_Logout`; индикация оставшихся попыток.
5. Список объектов (сертификаты, ключи): `C_FindObjectsInit` / `C_FindObjects`.
6. Генерация ключевой пары ГОСТ Р 34.10-2012: `C_GenerateKeyPair`.
7. Подпись тестовых данных (ГОСТ Р 34.11-2012 + ГОСТ Р 34.10-2012): `C_SignInit` / `C_Sign` — и проверка.

## 5а. Подпись RPM-пакетов (установлено 2026-07-19, после реальной ошибки на телефоне)

Факт с устройства владельца (Аврора 5.2): неподписанный RPM отклоняется установщиком с ошибкой **`Failed to install package (code: BadPackageSignature)`** — даже при разрешённой установке недоверенного ПО.

Как устроено (док-ция: developer.auroraos.ru, разделы `rpm_requirements`, `package_signing`, `tools/rpmsign-external`):

- Все установочные пакеты для Авроры должны нести **подпись разработчика** (X.509/PKCS#7 поверх RPM, алгоритм ГОСТ Р 34.10-2012). Профили подписи: Regular, Antivirus, Extended, Market, MDM.
- Для отладки OMP публикует **общедоступную тестовую пару профиля Regular**: `regular_key.pem` + `regular_cert.pem` (subject: «Noname developer (for testing only, do not use for production)», issuer: «Open Mobile Platform LLC Root Packages Certificate», срок до 2045 г.), URL: `https://developer.auroraos.ru/content-images/dev-documentation/regular_{key,cert}.pem` (портал отдаёт файлы только с браузерным User-Agent, иначе 403). Копия закоммичена в `ci/keys/`.
- Подпись: утилита `rpmsign-external` (пакет `rpmsign-external-tool`): `rpmsign-external sign --key regular_key.pem --cert regular_cert.pem pkg.rpm`; проверка — `verify`/`dump`. Ключ ГОСТ, поэтому подписываем внутри чрута Platform SDK (там есть ГОСТ-крипто); наш CI делает это в `ci/build-rpm.sh`.
- **С Авроры 5 пакеты на общедоступных (тестовых) ключах устанавливаются и запускаются только при включённом режиме разработчика** на устройстве; плюс нужна разрешённая установка недоверенного ПО.
- Боевой вариант — личные ключи из кабинета разработчика Авроры (требует регистрации OMP); для тестового приложения достаточно тестовой пары.
- Подпись тестовой парой **подтверждена на устройстве владельца** 2026-07-19: после подписи ошибка `BadPackageSignature` исчезла (сменилась на архитектурную, см. ниже).

## 5б. Архитектуры устройств (установлено 2026-07-19)

Телефон владельца — **32-битный**: aarch64-RPM отклонён с ошибкой `BadPackageArchitecture`. Аврора живёт на двух ARM-архитектурах: `armv7hl` (32 бит, многие серийные аппараты) и `aarch64` (64 бит); Platform SDK 5.2.1.200 предоставляет target-тарболлы для обеих (плюс x86_64 для эмулятора). CI собирает и подписывает оба варианта; владельцу нужен `*.armv7hl.rpm`.

Следствие для будущих версий: библиотека Рутокена должна браться **под armv7hl** (на rutoken.ru есть RPM для Авроры и ARM32, и ARM64 — см. §3).

## 5в. Параметры генерации ключевой пары на Рутокене (PKCS#11, для v0.4 этап C)

Источники: статья Актива [PKCS#11 для самых маленьких](https://habr.com/ru/companies/aktiv-company/articles/544748/), [Токены PKCS#11: генерация ключевой пары](https://habr.com/ru/post/400943/), форум Рутокен. Значения OID подтверждены; vendor-механизмы 512 (0xD432xxxx) — из заголовков Рутокен SDK, проверяются на устройстве.

**ГОСТ Р 34.10-2012 (256):**
- Механизм `CKM_GOSTR3410_KEY_PAIR_GEN` = `0x00001200`; тип ключа `CKK_GOSTR3410` = `0x00000030`.
- `CKA_GOSTR3410_PARAMS` (набор A, OID 1.2.643.2.2.35.1) = `06 07 2A 85 03 02 02 23 01`.
- `CKA_GOSTR3411_PARAMS` (хеш 2012-256, OID 1.2.643.7.1.1.2.2) = `06 08 2A 85 03 07 01 01 02 02`.

**ГОСТ Р 34.10-2012 (512):**
- Механизм `CKM_GOSTR3410_512_KEY_PAIR_GEN` = `0xD4321005` (vendor Актив); тип `CKK_GOSTR3410_512` = `0xD4321003` (vendor).
- `CKA_GOSTR3410_PARAMS` (набор A, OID 1.2.643.7.1.2.1.2.1) = `06 09 2A 85 03 07 01 02 01 02 01`.
- `CKA_GOSTR3411_PARAMS` (хеш 2012-512, OID 1.2.643.7.1.1.2.3) = `06 08 2A 85 03 07 01 01 02 03`.

**RSA:** `CKM_RSA_PKCS_KEY_PAIR_GEN` = `0x00000000`, `CKK_RSA` = `0x00000000`; в публичный шаблон — `CKA_MODULUS_BITS` (напр. 2048) и `CKA_PUBLIC_EXPONENT` = `01 00 01`. (Рутокен ЭЦП 3.0 — прежде всего ГОСТ; поддержка RSA проверяется на устройстве.)

**Атрибуты C_GenerateKeyPair:** публичный шаблон — `CKA_KEY_TYPE`, `CKA_TOKEN`=true, `CKA_ID`, `CKA_LABEL`, для ГОСТ `CKA_GOSTR3410_PARAMS`/`CKA_GOSTR3411_PARAMS`, для RSA `CKA_MODULUS_BITS`/`CKA_PUBLIC_EXPONENT`; приватный — то же + `CKA_PRIVATE`=true (плюс `CKA_GOSTR*_PARAMS` для ГОСТ). Генерация приватного ключа требует входа по PIN. Коды атрибутов: `CKA_TOKEN`=0x01, `CKA_PRIVATE`=0x02, `CKA_MODULUS_BITS`=0x121, `CKA_PUBLIC_EXPONENT`=0x122, `CKA_GOSTR3410_PARAMS`=0x250, `CKA_GOSTR3411_PARAMS`=0x251. `C_GenerateKeyPair` — позиция 60 в `CK_FUNCTION_LIST`.

### 5г. Запрос на сертификат PKCS#10 (CSR) с ГОСТ — для v0.7

Источники: RFC 4491 (использование ГОСТ Р 34.10 в PKIX), RFC 9215 (ГОСТ 2012 в X.509), заголовки Рутокен SDK, [статья Актива](https://habr.com/ru/companies/aktiv-company/articles/544748/). **Порядок байтов открытого ключа и подписи ГОСТ в DER — известная тонкость; проверяется на устройстве через openssl с ГОСТ-движком.**

```
CertificationRequest      ::= SEQUENCE { info CertificationRequestInfo, sigAlg AlgorithmIdentifier, sig BIT STRING }
CertificationRequestInfo  ::= SEQUENCE { version INTEGER(0), subject Name, spki SubjectPublicKeyInfo, attributes [0] IMPLICIT SET }
```

- **Подпись CSR — без нового ABI:** переиспользуем уже заведённые `C_SignInit`/`C_Sign` (№43/44) с механизмом «подпись с хешем», который хеширует и подписывает произвольные данные (весь DER `CertificationRequestInfo`) за один `C_Sign`:
  - `CKM_GOSTR3410_WITH_GOSTR3411_12_256` = `0xD4321008` (vendor Актив), подпись 64 байта;
  - `CKM_GOSTR3410_WITH_GOSTR3411_12_512` = `0xD4321009` (vendor), подпись 128 байт;
  - RSA: `CKM_SHA256_RSA_PKCS` = `0x00000040`.
- **SubjectPublicKeyInfo (ГОСТ):** алгоритм-OID открытого ключа 2012-256 = 1.2.643.7.1.1.1.1 (`06 08 2A 85 03 07 01 01 01 01`), 512 = 1.2.643.7.1.1.1.2 (`…01 02`); параметры — `SEQUENCE { publicKeyParamSet OID, digestParamSet OID }` берём **прямо с токена** (атрибуты `CKA_GOSTR3410_PARAMS`/`CKA_GOSTR3411_PARAMS` уже содержат DER OID). Сам ключ — `CKA_VALUE` (OCTET STRING `04 40 <64>` / `04 80 <128>`), кладём как содержимое `BIT STRING` (unused-bits `00`).
- **signatureAlgorithm:** id-tc26-signwithdigest-gost3410-12-256 = 1.2.643.7.1.1.3.2 (`06 08 2A 85 03 07 01 01 03 02`), 512 = `…03 03`. Без параметров.
- **Подпись в CSR:** сырой результат `C_Sign` (r||s, 64/128 байт) в `BIT STRING`. Порядок байтов сверяем на устройстве.
- **Subject Name (DN):** `SEQUENCE OF RDN`, RDN = `SET { SEQUENCE { OID, value } }`. OID: CN 2.5.4.3 (`55 04 03`), O 2.5.4.10 (`…0A`), OU 2.5.4.11 (`…0B`), C 2.5.4.6 (`…06`, `PrintableString`), L 2.5.4.7, ST 2.5.4.8, emailAddress 1.2.840.113549.1.9.1 (`2A 86 48 86 F7 0D 01 09 01`, `IA5String`). Текстовые значения — `UTF8String` (0x0C).
- **Проверка:** экспорт CSR в PEM (`-----BEGIN CERTIFICATE REQUEST-----`), затем на ПК `openssl req -in req.pem -verify -noout -text` с ГОСТ-движком (задокументировать как).

## 6. Открытые вопросы (проверять на следующих этапах)

1. Входят ли `pcscd` и NFC-handler в стандартную поставку Авроры, или ставятся отдельными пакетами (например, вместе с приложением «Рутокен»)? Доступен ли pcscd стороннему приложению из песочницы?
2. Какие разрешения (Permissions) нужны приложению для USB/NFC/смарт-карт на Аврора 5 и как их декларировать (.desktop/манифест).
3. Как поставлять `librtpkcs11ecp.so`: зависимость RPM (`Requires:`), вложение `.so` в пакет приложения или требование предустановки.
4. Целевая версия Авроры (4.0.2+ / 5.x) и тестовые устройства; наличие физического Рутокен ЭЦП 3.0 NFC.
5. Работоспособность в эмуляторе Аврора SDK (x86_64): поддерживается ли библиотека и как пробрасывать USB-токен.
6. Доступность hub.mos.ru и download.rutoken.ru из среды сборки агентов/CI.

## 6а. Фактическая диагностика на Авроре 5.2 (2026-07-19)

Владелец установил `v0.0.2` на физический 32-битный телефон с Авророй 5.2 и сообщил следующие результаты:

- все строки диагностического экрана зелёные: доступны `nfcd`, NFC-адаптер, `libpcsclite` и контекст `pcscd`;
- при подключении Рутокен ЭЦП по USB появляется дополнительный PC/SC-ридер с именем **`Aktiv Rutoken ECP 00`**;
- диагностика успешно выполняется с текущей декларацией приложения `Permissions=NFC`, то есть отдельное desktop-разрешение для выполненных вызовов PC/SC/USB на этом устройстве не потребовалось.

Это подтверждает на реальном устройстве базовый путь USB `Рутокен → CCID/pcscd → libpcsclite → приложение`.

**Имена PC/SC-ридеров на Авроре (подтверждено 2026-07-20, v0.1 на устройстве):**

| Подключение | Имя слота/ридера (`CK_SLOT_INFO.slotDescription`) |
|---|---|
| **NFC** | `ifd-nfcd-handler 00 00` |
| **USB** | `Aktiv Rutoken ECP 00 00` |

То есть NFC-токен действительно виден через тот же PKCS#11/PC/SC, но через отдельный ifd-handler `ifd-nfcd-handler` (мост к стеку `nfcd`), а USB — через штатный CCID-handler Актива. Эвристика определения типа подключения (`pkcs11_tokens.cpp::connectionType`): имя содержит `nfc` → NFC (ловит `ifd-nfcd-handler`), иначе `aktiv`/`rutoken`/`ccid`/`usb` → USB. На обоих реальных токенах владельца классификация верна.

## 6б. Проверка архитектуры RPM в CI (2026-07-19)

Последовательные `mb2 build` для разных targets нельзя выполнять в одном исходном каталоге без полной очистки: qmake меняет target-параметры, но make может повторно использовать уже существующие object-файлы. Реальный результат такого загрязнения: RPM с заголовком `aarch64` содержал ARM32 ELF и loader `ld-linux-armhf.so.3`.

Исправленная схема использует независимый GitHub Actions matrix job для каждой архитектуры. После упаковки `ci/verify-rpm.sh` извлекает бинарник из RPM и проверяет:

- заголовок RPM: `armv7hl` либо `aarch64`;
- ELF machine: `ARM` либо `AArch64`;
- dynamic loader: `ld-linux-armhf.so.3` либо `ld-linux-aarch64.so.1`;
- наличие метаданных подписи публичного тестового сертификата OMP, subgroup `regular`.

Run `29701204751` подтвердил корректную пару `0.0.2-2`. Предупреждения rpmlint `no-changelogname-tag` и `unstripped-binary-or-object` оставлены как известные особенности тестовой PSDK-сборки: официальный OMP ApplicationTemplate не содержит changelog, а диагностическое приложение сохраняет отладочную информацию. Они не заменяют и не отключают жёсткую проверку архитектуры и подписи.

## 6c. Поставка PKCS#11-библиотеки в v0.0.3 (2026-07-19)

Официальная страница загрузки Рутокен предлагает для Авроры версию **2.19.0.0** от 17.04.2026 отдельно для ARM32 и ARM64. Зафиксированы прямые официальные пакеты:

- armv7hl: `https://download.rutoken.ru/Rutoken/PKCS11Lib/2.19.0.0/Aurora/armv7/ru.rutoken.librtpkcs11ecp-2.19.0.0-1.armv7hl.rpm`, SHA-256 `b9f0da43dd884a95b629155cad3c21a4701ddc0220798bcc046c0146b4cd88c3`;
- aarch64: `https://download.rutoken.ru/Rutoken/PKCS11Lib/2.19.0.0/Aurora/aarch64/ru.rutoken.librtpkcs11ecp-2.19.0.0-1.aarch64.rpm`, SHA-256 `c16d8c2006631e9330a1ee6c8b2f60e5ddbfaf7112a0d5056e3b21ca92e69921`.

Оба RPM устанавливают библиотеку по одинаковому системному пути `/usr/lib/3rdparty/ru.rutoken.librtpkcs11ecp/librtpkcs11ecp.so`; armv7hl содержит ELF32 ARM, aarch64 — ELF64 AArch64. SONAME — `librtpkcs11ecp.so`, зависимость — `libpcsclite.so.1`; экспортируются `C_GetFunctionList`, `C_Initialize`, `C_Finalize`, `C_GetInfo`.

Изучено официальное лицензионное соглашение Рутокен. Разделы 4.3 и 4.4 разрешают безвозмездное воспроизведение и распространение ПО при сохранении неизменного вида и целостности; модификация и декомпиляция не допускаются. Поэтому библиотека **не распаковывается внутрь MIT-пакета приложения**. CI скачивает, проверяет и публикует рядом исходный официальный RPM без изменений; пользователь сначала устанавливает его, затем приложение. Жёсткий `Requires:` не добавлен: официальный пакет отсутствует в стандартном репозитории зависимостей, а диагностическое приложение должно устанавливаться и честно показывать отсутствие модуля.

Для компиляции использован только минимально нужный ABI-префикс PKCS#11 v2.40. Источник — функционально эквивалентные заголовки Latchset `pkcs11-headers`, каталог `public-domain/2.40`, commit `c5e61990c5621a9b955fc208644fe8145ac0a75d`; авторы явно поместили переписанные с нуля заголовки в public domain. В `src/pkcs11_minimal.h` сохранены атрибуция, версия, только структуры `CK_VERSION`, `CK_INFO` и начало `CK_FUNCTION_LIST`, а также compile-time проверки обязательного one-byte packing.

## 7. Источники

- https://hub.mos.ru/auroraos — группа ОМП на Мос.Хабе (подгруппы demos/examples/flutter/edu)
- https://developer.auroraos.ru/demos — каталог демо и примеров
- https://developer.auroraos.ru/doc/software_development/examples — документация по примерам
- https://www.omp.ru/news1/tpost/9psx1zl3m1-open-source-proekti-dlya-os-avrora-stali — новость о переносе на Mos.Hub
- https://www.mos.ru/news/item/161601073/ — новость mos.ru
- https://hub.mos.ru/auroraos/demos/NfcUseCases — NFC-демо (pcsc-lite + nfcd)
- https://hub.mos.ru/auroraos/demos/ApplicationTemplate — шаблон приложения
- https://hub.mos.ru/auroraos/demos/UsbUseCases — USB-демо
- https://www.rutoken.ru/products/all/rutoken-ecp-3/ — Рутокен ЭЦП 3.0
- https://www.rutoken.ru/support/download/pkcs/ — загрузки PKCS#11 (RPM для Авроры ARM32/ARM64, v2.19.0.0)
- https://www.rutoken.ru/download/license/License_Agreement_Rutoken.pdf — лицензионное соглашение, условия распространения неизменного ПО (разделы 4.3–4.4)
- https://github.com/latchset/pkcs11-headers/tree/main/public-domain/2.40 — public-domain ABI-заголовки PKCS#11 v2.40
- https://www.rutoken.ru/developers/sdk/ — Рутокен SDK
- https://dev.rutoken.ru/pages/viewpage.action?pageId=3178509 — rtPKCS11ECP
- https://dev.rutoken.ru/pages/viewpage.action?pageId=78479413 — начало работы с Рутокен ЭЦП 3.0 NFC
- https://auroraos.ru/applications/rutoken — приложение «Рутокен» в каталоге Авроры
- https://forum.rutoken.ru/topic/3779/ — Bluetooth-Рутокен на Авроре не поддерживается; ограничение КриптоПро CSP
- https://developer.auroraos.ru/doc/extended/flutter — документация Flutter для Авроры
- https://developer.auroraos.ru/doc/software_development/guidelines/rpm_requirements — требования к установочным пакетам (обязательная подпись)
- https://developer.auroraos.ru/doc/sdk/app_development/packaging/package_signing — подписание пакетов; ссылки на тестовую пару regular_key/regular_cert; про блокировку общедоступных ключей без режима разработчика на Аврора 5
- https://developer.auroraos.ru/doc/sdk/tools/rpmsign_external — утилита rpmsign-external (пакет rpmsign-external-tool), синтаксис sign/verify/dump
