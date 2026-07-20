#ifndef TOKENWATCHER_H
#define TOKENWATCHER_H

#include <QtCore/QObject>
#include <QtCore/QLibrary>
#include <QtCore/QString>
#include <QtCore/QVariantList>

class QTimer;

// Живое наблюдение за подключёнными токенами Рутокен (USB и NFC).
// Библиотека PKCS#11 загружается один раз; каждый опрос в рабочем потоке
// выполняет свежий C_Initialize → перечисление → C_Finalize, поэтому
// подхватывает и появление нового USB-ридера, и появление/исчезновение
// NFC-карты. UI-свойство tokens обновляется только при изменении набора.
class TokenWatcher : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList tokens READ tokens NOTIFY tokensChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool libraryReady READ libraryReady NOTIFY statusChanged)

public:
    explicit TokenWatcher(QObject *parent = nullptr);
    ~TokenWatcher() override;

    QVariantList tokens() const { return m_tokens; }
    QString status() const { return m_status; }
    bool libraryReady() const { return m_getFunctionList != nullptr; }

    Q_INVOKABLE void start();
    Q_INVOKABLE void refresh();

signals:
    void tokensChanged();
    void statusChanged();
    void polled(const QVariantList &cards, const QString &error); // из рабочего потока

private:
    void doPoll();
    void onPolled(const QVariantList &cards, const QString &error);
    void setStatus(const QString &status);

    QLibrary m_library;
    QFunctionPointer m_getFunctionList = nullptr;
    QTimer *m_timer = nullptr;
    QVariantList m_tokens;
    QString m_status;
    QString m_signature;
    bool m_polling = false;
};

#endif // TOKENWATCHER_H
