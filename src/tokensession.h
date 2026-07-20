#ifndef TOKENSESSION_H
#define TOKENSESSION_H

#include <QtCore/QObject>
#include <QtCore/QLibrary>
#include <QtCore/QString>
#include <QtCore/QVariantList>

// Проверка PIN пользователя на конкретном слоте. Операция выполняется одним
// изолированным циклом в рабочем потоке под общим мьютексом PKCS#11:
// C_Initialize → C_OpenSession → C_Login → [C_GetTokenInfo для флагов] →
// C_Logout → C_CloseSession → C_Finalize. PIN не логируется и обнуляется
// в памяти сразу после использования.
class TokenSession : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(int outcome READ outcome NOTIFY changed) // 0 — нет, 1 — успех, -1 — ошибка
    Q_PROPERTY(QString result READ result NOTIFY changed)
    Q_PROPERTY(QVariantList objects READ objects NOTIFY changed)

public:
    explicit TokenSession(QObject *parent = nullptr);

    bool busy() const { return m_busy; }
    int outcome() const { return m_outcome; }
    QString result() const { return m_result; }
    QVariantList objects() const { return m_objects; }

    // Вход по PIN + чтение всех объектов (сертификаты и ключи).
    Q_INVOKABLE void login(qulonglong slotId, const QString &pin);
    // Чтение только сертификатов без входа (они видны без PIN).
    Q_INVOKABLE void preview(qulonglong slotId);
    Q_INVOKABLE void clear();

signals:
    void changed();
    void finished(int outcome, const QString &message, const QVariantList &objects); // из рабочего потока

private:
    void run(qulonglong slotId, const QString &pin, bool doLogin);
    void onFinished(int outcome, const QString &message, const QVariantList &objects);

    QLibrary m_library;
    QFunctionPointer m_getFunctionList = nullptr;
    bool m_busy = false;
    int m_outcome = 0;
    QString m_result;
    QVariantList m_objects;
};

#endif // TOKENSESSION_H
