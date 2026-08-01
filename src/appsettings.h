#ifndef APPSETTINGS_H
#define APPSETTINGS_H

#include <QtCore/QList>
#include <QtCore/QObject>
#include <QtCore/QVariantList>

class AppSettings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool cryptoProEnabled READ cryptoProEnabled WRITE setCryptoProEnabled
               NOTIFY cryptoProEnabledChanged)
    // Набор ГОСТ-провайдеров КриптоПро, которыми разрешено работать. Влияет и на
    // чтение, и на создание контейнеров.
    Q_PROPERTY(QVariantList cryptoProProviderTypes READ cryptoProProviderTypes
               NOTIFY cryptoProProviderTypesChanged)

public:
    explicit AppSettings(QObject *parent = nullptr);

    bool cryptoProEnabled() const { return m_cryptoProEnabled; }
    void setCryptoProEnabled(bool enabled);

    // Известные приложению типы провайдеров, в порядке показа.
    static QList<int> knownProviderTypes();

    QList<int> cryptoProProviderTypeList() const { return m_providerTypes; }
    QVariantList cryptoProProviderTypes() const;

    // Последний включённый тип выключить нельзя: пустой набор означал бы, что
    // КриптоПро включён, но не читает ничего, — это не состояние, а ловушка.
    Q_INVOKABLE void setProviderTypeEnabled(int type, bool enabled);
    // Первый включённый тип: форме создания нужен корректный вариант по
    // умолчанию, даже если ранее выбранный провайдер уже выключен.
    Q_INVOKABLE int firstEnabledProviderType() const;

signals:
    void cryptoProEnabledChanged();
    void cryptoProProviderTypesChanged();

private:
    bool m_cryptoProEnabled = false;
    QList<int> m_providerTypes;
};

#endif // APPSETTINGS_H
