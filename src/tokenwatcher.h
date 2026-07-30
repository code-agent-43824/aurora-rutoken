#ifndef TOKENWATCHER_H
#define TOKENWATCHER_H

#include <QtCore/QObject>
#include <QtCore/QFuture>
#include <QtCore/QLibrary>
#include <QtCore/QProcess>
#include <QtCore/QString>
#include <QtCore/QVariantList>

// Живое наблюдение за подключёнными Рутокенами (USB и NFC).
// Отдельный helper-процесс блокируется в C_WaitForSlotEvent; основной процесс
// перечисляет устройства только после реального события, при старте или по
// ручному refresh. Поэтому фонового опроса и мигания устройства нет.
class TokenWatcher : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList tokens READ tokens NOTIFY tokensChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool libraryReady READ libraryReady NOTIFY statusChanged)

public:
    explicit TokenWatcher(QObject *parent = nullptr);
    ~TokenWatcher() override;

    static int runSlotEventHelper();

    QVariantList tokens() const { return m_tokens; }
    QString status() const { return m_status; }
    bool libraryReady() const { return m_getFunctionList != nullptr; }

    Q_INVOKABLE void start();
    Q_INVOKABLE void refresh();

signals:
    void tokensChanged();
    void statusChanged();
    void snapshotReady(const QVariantList &cards, const QString &error);

private:
    void startEventHelper();
    void readEventHelperOutput();
    void eventHelperFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void eventHelperError(QProcess::ProcessError error);
    void doSnapshot();
    void onSnapshotReady(const QVariantList &cards, const QString &error);
    void setStatus(const QString &status);

    QLibrary m_library;
    QFunctionPointer m_getFunctionList = nullptr;
    QProcess m_eventHelper;
    QFuture<void> m_snapshotFuture;
    QByteArray m_eventHelperOutput;
    QVariantList m_tokens;
    QString m_status;
    QString m_signature;
    bool m_snapshotRunning = false;
    bool m_snapshotPending = false;
    bool m_eventHelperReady = false;
    bool m_stopping = false;
};

#endif // TOKENWATCHER_H
