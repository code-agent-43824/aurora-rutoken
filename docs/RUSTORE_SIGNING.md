# Ручное подписание RPM для RuStore

Стабильные RPM в GitHub Release сначала подписаны общедоступным тестовым
сертификатом OMP. Для загрузки в RuStore RPM приложения нужно переподписать
личным сертификатом разработчика. Это делает workflow
`Sign latest stable release for RuStore`.

Workflow формирует подпись **разработчика**. По официальным требованиям пакет
для магазина также должен получить подпись центра доверия RuStore; этот второй
слой относится к процедуре приёма/публикации в магазине и не использует
закрытый ключ разработчика из данного workflow.

## Модель запуска

- единственный trigger — `workflow_dispatch`; push, tag и расписание отсутствуют;
- workflow сам определяет последний опубликованный стабильный GitHub Release
  (`releases/latest`) и фиксирует его tag как неизменяемый источник RPM;
- инструменты подписания берутся из вручную выбранной ветки workflow (штатно
  `main`), поэтому старый release tag не обязан содержать новый CI-код;
- отдельные matrix jobs подписывают `armv7hl` и `aarch64`;
- выбирается только RPM `ru.codeagent43824.rutokentestapp`; официальный RPM
  библиотеки Рутокен не изменяется;
- исходная тестовая developer-подпись заменяется через
  `rpmsign-external sign --force`;
- результат доступен 30 дней в двух Actions artifacts вместе с SHA-256 и tag
  исходного Release. Стабильный Release и `ci-latest` workflow не изменяет.

## GitHub Actions Secrets

В `Settings → Secrets and variables → Actions → New repository secret` нужны:

1. `RUSTORE_SIGNING_KEY_PEM` — **полное содержимое зашифрованного закрытого
   PEM-ключа**, соответствующего сертификату. Это не присланный файл
   `*-cert.pem`: сертификат содержит только открытый ключ.
2. `RUSTORE_SIGNING_KEY_PASSPHRASE` — кодовая фраза шифрования этого PEM.

Публичный сертификат не является секретом и закреплён в
`ci/keys/rustore_developer_cert.pem`. Workflow принимает только сертификат с
SHA-256 fingerprint
`1989e9224759048af5c4efc70fb65bbc121443413634582e6a7bfbfc7614f6ac`.

Не помещать закрытый ключ в репозиторий, Actions variables, workflow inputs,
комментарии, issue или логи. GitHub Secrets должны быть repository secrets:
тогда после однократной настройки каждый последующий ручной запуск полностью
автономен.

## Запуск

`Actions → Sign latest stable release for RuStore → Run workflow`.

Успешный прогон создаёт два артефакта:

- `rutokentestapp-<tag>-armv7hl-rustore-signed`;
- `rutokentestapp-<tag>-aarch64-rustore-signed`.

Workflow аварийно завершается до подписи, если отсутствует секрет, закрытый
ключ не соответствует сертификату, сертификат изменён, stable Release не
найден, RPM приложения не единственный, архитектура/имя пакета неверны или
исходная тестовая подпись отсутствует.
