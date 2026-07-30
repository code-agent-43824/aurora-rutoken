#ifndef CRYPTOPROSESSION_H
#define CRYPTOPROSESSION_H

#include <QtCore/QObject>
#include <QtCore/QProcess>
#include <QtCore/QTimer>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>

class CryptoProSession : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY changed)
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString libraryPath READ libraryPath NOTIFY changed)
    Q_PROPERTY(QStringList loadedLibraries READ loadedLibraries NOTIFY changed)
    Q_PROPERTY(QVariantList providers READ providers NOTIFY changed)
    Q_PROPERTY(QVariantList containers READ containers NOTIFY changed)
    Q_PROPERTY(QVariantList certificates READ certificates NOTIFY changed)

public:
    explicit CryptoProSession(QObject *parent = nullptr);
    ~CryptoProSession() override;

    static int runScanHelper();

    bool enabled() const { return m_enabled; }
    bool available() const { return m_available; }
    bool busy() const { return m_busy; }
    QString status() const { return m_status; }
    QString libraryPath() const { return m_libraryPath; }
    QStringList loadedLibraries() const { return m_loadedLibraries; }
    QVariantList providers() const { return m_providers; }
    QVariantList containers() const { return m_containers; }
    QVariantList certificates() const { return m_certificates; }

    void setEnabled(bool enabled);
    Q_INVOKABLE void refresh();

signals:
    void changed();

private:
    void readHelperOutput();
    void finishHelper(int exitCode, QProcess::ExitStatus exitStatus);
    void helperError(QProcess::ProcessError error);
    void helperTimedOut();
    void failRefresh(const QString &message);

    QProcess m_helper;
    QTimer m_helperTimer;
    QByteArray m_helperOutput;
    bool m_enabled = false;
    bool m_available = false;
    bool m_busy = false;
    bool m_refreshPending = false;
    QString m_status;
    QString m_libraryPath;
    QStringList m_loadedLibraries;
    QVariantList m_providers;
    QVariantList m_containers;
    QVariantList m_certificates;
};

#endif // CRYPTOPROSESSION_H
