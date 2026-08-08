#ifndef CRYPTOPROSESSION_H
#define CRYPTOPROSESSION_H

#include <QtCore/QList>
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
    Q_PROPERTY(QString cspVersion READ cspVersion NOTIFY changed)
    // Счётчик завершённых проходов: мастер NFC ждёт именно свой результат, а не
    // первое попавшееся завершение.
    Q_PROPERTY(int scanSerial READ scanSerial NOTIFY changed)
    // Создание контейнера (v1.3): состояние отдельное от чтения.
    Q_PROPERTY(bool createBusy READ createBusy NOTIFY changed)
    Q_PROPERTY(int createOutcome READ createOutcome NOTIFY changed) // 0/1/-1
    Q_PROPERTY(QString createResult READ createResult NOTIFY changed)
    Q_PROPERTY(QString lastRequest READ lastRequest NOTIFY changed) // PEM PKCS#10
    Q_PROPERTY(QStringList loadedLibraries READ loadedLibraries NOTIFY changed)
    Q_PROPERTY(QVariantList providers READ providers NOTIFY changed)
    // Считыватели КриптоПро: режим контейнера задаётся выбором считывателя,
    // поэтому форма создания предлагает то, что есть на устройстве.
    Q_PROPERTY(QVariantList readers READ readers NOTIFY changed)
    Q_PROPERTY(QVariantList containers READ containers NOTIFY changed)
    Q_PROPERTY(QVariantList certificates READ certificates NOTIFY changed)

public:
    explicit CryptoProSession(QObject *parent = nullptr);
    ~CryptoProSession() override;

    static int runScanHelper();
    // Режим записи (создание контейнера, запрос на сертификат): запрос читается
    // из stdin, чтобы PIN-код не попадал в аргументы процесса.
    static int runWriteHelper();

    bool enabled() const { return m_enabled; }
    bool available() const { return m_available; }
    bool busy() const { return m_busy; }
    QString status() const { return m_status; }
    QString libraryPath() const { return m_libraryPath; }
    QString cspVersion() const { return m_cspVersion; }
    int scanSerial() const { return m_scanSerial; }
    bool createBusy() const { return m_createBusy; }
    int createOutcome() const { return m_createOutcome; }
    QString createResult() const { return m_createResult; }
    QString lastRequest() const { return m_lastRequest; }

    // Создаёт контейнер и неэкспортируемую ключевую пару ГОСТ-2012 на выбранном
    // считывателе. Выполняется в отдельном helper-процессе.
    Q_INVOKABLE void createContainer(const QString &reader, const QString &container,
                                     int providerType, const QString &pin);
    // Формирует PKCS#10 для существующего контейнера средствами провайдера.
    Q_INVOKABLE void createCertificateRequest(const QString &container, int providerType,
                                              const QString &pin, const QVariantMap &subject);
    Q_INVOKABLE bool saveRequestToFile(const QString &name);
    QStringList loadedLibraries() const { return m_loadedLibraries; }
    QVariantList providers() const { return m_providers; }
    QVariantList readers() const { return m_readers; }
    QVariantList containers() const { return m_containers; }
    QVariantList certificates() const { return m_certificates; }

    void setEnabled(bool enabled);
    // Набор ГОСТ-провайдеров из настроек: ими и только ими выполняется чтение и
    // разрешается создание контейнеров.
    void setProviderTypes(const QList<int> &types);
    Q_INVOKABLE void refresh();
    // Решает, нужен ли новый CAPI-проход: он заметно медленнее PKCS#11, а по
    // NFC особенно, поэтому лишних чтений быть не должно.
    void syncWithTokens(const QVariantList &tokens);

signals:
    void changed();

private:
    void readHelperOutput();
    void finishHelper(int exitCode, QProcess::ExitStatus exitStatus);
    void helperError(QProcess::ProcessError error);
    void helperTimedOut();
    void failRefresh(const QString &message);
    void finishCreate(int exitCode, QProcess::ExitStatus exitStatus);
    void failCreate(const QString &message);

    QProcess m_helper;
    QTimer m_helperTimer;
    QByteArray m_helperOutput;
    bool m_enabled = false;
    bool m_available = false;
    bool m_busy = false;
    bool m_refreshPending = false;
    QString m_status;
    QString m_libraryPath;
    QString m_cspVersion;
    QStringList m_scannedReaders;
    QList<int> m_providerTypes;
    bool m_syncedOnce = false;
    int m_scanSerial = 0;
    QProcess m_createHelper;
    QTimer m_createTimer;
    QByteArray m_createOutput;
    QByteArray m_createPayload;
    bool m_createBusy = false;
    int m_createOutcome = 0;
    QString m_createResult;
    QString m_lastRequest;
    QStringList m_loadedLibraries;
    QVariantList m_providers;
    QVariantList m_readers;
    QVariantList m_containers;
    QVariantList m_certificates;
};

#endif // CRYPTOPROSESSION_H
