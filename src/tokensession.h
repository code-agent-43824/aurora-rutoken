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
    // Генерация ключевой пары на токене (вход по PIN, R/W-сессия, C_GenerateKeyPair),
    // затем перечитывание объектов. algorithm: "gost256"/"gost512"/"rsa2048"/"rsa4096".
    Q_INVOKABLE void generateKeyPair(qulonglong slotId, const QString &pin,
                                     const QString &algorithm, const QString &label);
    // Импорт X.509-сертификата из файла на токен (вход по PIN, R/W-сессия,
    // C_CreateObject) с приклеиванием к ключевой паре по открытому ключу; затем
    // перечитывание объектов.
    Q_INVOKABLE void importCertificate(qulonglong slotId, const QString &pin,
                                       const QString &filePath, const QString &label);
    Q_INVOKABLE void clear();

    // Экспорт сертификата (тело из derB64, без закрытого ключа) в выбранный
    // пользователем формат ("pem"/"der"), каталог и имя файла. Возвращает
    // человекочитаемое сообщение (путь или ошибку). Синхронно — файл небольшой.
    Q_INVOKABLE QString exportCertificate(const QString &derB64, const QString &format,
                                          const QString &dirPath, const QString &baseName);
    // Каталог по умолчанию для плейсхолдера пути (загрузки → документы → дом).
    Q_INVOKABLE QString defaultExportDir();

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
