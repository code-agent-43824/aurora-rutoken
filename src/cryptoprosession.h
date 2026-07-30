#ifndef CRYPTOPROSESSION_H
#define CRYPTOPROSESSION_H

#include <QtCore/QFutureWatcher>
#include <QtCore/QLibrary>
#include <QtCore/QObject>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>
#include <QtCore/QVector>

class CryptoProSession : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString libraryPath READ libraryPath NOTIFY changed)
    Q_PROPERTY(QVariantList providers READ providers NOTIFY changed)
    Q_PROPERTY(QVariantList containers READ containers NOTIFY changed)
    Q_PROPERTY(QVariantList certificates READ certificates NOTIFY changed)

public:
    explicit CryptoProSession(QObject *parent = nullptr);
    ~CryptoProSession() override;

    bool available() const { return m_available; }
    bool busy() const { return m_busy; }
    QString status() const { return m_status; }
    QString libraryPath() const { return m_libraryPath; }
    QVariantList providers() const { return m_providers; }
    QVariantList containers() const { return m_containers; }
    QVariantList certificates() const { return m_certificates; }

    Q_INVOKABLE void refresh();

signals:
    void changed();

private:
    bool loadLibrary();
    void finishRefresh();

    QLibrary m_library;
    QFutureWatcher<QVariantMap> m_watcher;
    QVector<QFunctionPointer> m_functions;
    bool m_available = false;
    bool m_busy = false;
    QString m_status;
    QString m_libraryPath;
    QVariantList m_providers;
    QVariantList m_containers;
    QVariantList m_certificates;
};

#endif // CRYPTOPROSESSION_H
