#include "appsettings.h"

#include <QtCore/QSettings>

namespace {
const char kCryptoProEnabledKey[] = "features/cryptoProEnabled";
}

AppSettings::AppSettings(QObject *parent)
    : QObject(parent)
{
    // Отсутствующее значение намеренно означает false: КриптоПро является
    // opt-in backend и до явного включения не должен загружаться.
    QSettings settings;
    m_cryptoProEnabled = settings.value(
                QString::fromLatin1(kCryptoProEnabledKey), false).toBool();
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
