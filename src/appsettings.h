#ifndef APPSETTINGS_H
#define APPSETTINGS_H

#include <QtCore/QObject>

class AppSettings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool cryptoProEnabled READ cryptoProEnabled WRITE setCryptoProEnabled
               NOTIFY cryptoProEnabledChanged)

public:
    explicit AppSettings(QObject *parent = nullptr);

    bool cryptoProEnabled() const { return m_cryptoProEnabled; }
    void setCryptoProEnabled(bool enabled);

signals:
    void cryptoProEnabledChanged();

private:
    bool m_cryptoProEnabled = false;
};

#endif // APPSETTINGS_H
