#include "appsettings.h"

#include <QtCore/QSettings>
#include <QtCore/QStringList>

#include <algorithm>

namespace {
const char kCryptoProEnabledKey[] = "features/cryptoProEnabled";
const char kCryptoProProviderTypesKey[] = "cryptopro/providerTypes";

// Основной провайдер: ГОСТ Р 34.10-2012/256. Он же значение по умолчанию —
// каждый лишний провайдер добавляет отдельный опрос носителя.
const int kDefaultProviderType = 80;
}

QList<int> AppSettings::knownProviderTypes()
{
    // 80 — ГОСТ Р 34.10-2012/256, 81 — ГОСТ Р 34.10-2012/512,
    // 75 — ГОСТ Р 34.10-2001 (PROV_GOST_2001_DH).
    return QList<int>() << 80 << 81 << 75;
}

AppSettings::AppSettings(QObject *parent)
    : QObject(parent)
{
    // Отсутствующее значение намеренно означает false: КриптоПро является
    // opt-in backend и до явного включения не должен загружаться.
    QSettings settings;
    m_cryptoProEnabled = settings.value(
                QString::fromLatin1(kCryptoProEnabledKey), false).toBool();

    // Хранится списком номеров через запятую. Неизвестные номера отбрасываем:
    // работать можно только тем, что приложение действительно умеет показать.
    const QStringList stored = settings.value(
                QString::fromLatin1(kCryptoProProviderTypesKey), QString())
            .toString().split(QLatin1Char(','), QString::SkipEmptyParts);
    const QList<int> known = knownProviderTypes();
    for (const QString &item : stored) {
        bool ok = false;
        const int type = item.trimmed().toInt(&ok);
        if (ok && known.contains(type) && !m_providerTypes.contains(type))
            m_providerTypes.append(type);
    }
    if (m_providerTypes.isEmpty())
        m_providerTypes.append(kDefaultProviderType);
}

void AppSettings::setCryptoProEnabled(bool enabled)
{
    if (m_cryptoProEnabled == enabled)
        return;
    m_cryptoProEnabled = enabled;
    QSettings settings;
    settings.setValue(QString::fromLatin1(kCryptoProEnabledKey), enabled);
    settings.sync();
    emit cryptoProEnabledChanged();
}

QVariantList AppSettings::cryptoProProviderTypes() const
{
    QVariantList out;
    for (const int type : m_providerTypes)
        out.append(type);
    return out;
}

int AppSettings::firstEnabledProviderType() const
{
    // Порядок показа, а не порядок сохранения: пользователь ожидает увидеть
    // первым основной провайдер, а не тот, что он включил раньше остальных.
    const QList<int> known = knownProviderTypes();
    for (const int type : known) {
        if (m_providerTypes.contains(type))
            return type;
    }
    return kDefaultProviderType;
}

void AppSettings::setProviderTypeEnabled(int type, bool enabled)
{
    if (!knownProviderTypes().contains(type))
        return;
    if (enabled == m_providerTypes.contains(type))
        return;
    if (!enabled && m_providerTypes.size() == 1)
        return;                     // последний включённый остаётся включённым

    if (enabled)
        m_providerTypes.append(type);
    else
        m_providerTypes.removeAll(type);
    std::sort(m_providerTypes.begin(), m_providerTypes.end());

    QStringList stored;
    for (const int item : m_providerTypes)
        stored.append(QString::number(item));
    QSettings settings;
    settings.setValue(QString::fromLatin1(kCryptoProProviderTypesKey),
                      stored.join(QStringLiteral(",")));
    settings.sync();
    emit cryptoProProviderTypesChanged();
}
