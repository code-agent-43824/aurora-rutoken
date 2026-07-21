#ifndef TOKENSESSION_H
#define TOKENSESSION_H

#include <QtCore/QByteArray>
#include <QtCore/QObject>
#include <QtCore/QLibrary>
#include <QtCore/QString>
#include <QtCore/QVariantList>

// Проверка PIN пользователя на конкретном слоте. Операция выполняется одним
// изолированным циклом в рабочем потоке под общим мьютексом PKCS#11:
// C_Initialize → C_OpenSession → C_Login → [C_GetTokenInfo для флагов] →
// C_Logout → C_CloseSession → C_Finalize.
//
// Запоминание PIN (для USB): после успешного login() PIN хранится в оперативной
// памяти (m_cachedPin) и переиспользуется генерацией/импортом без повторного
// ввода — до logout(), отключения слота (retainUsbSlot) или закрытия приложения.
// PIN не логируется и обнуляется в памяти при сбросе кэша.
class TokenSession : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(int outcome READ outcome NOTIFY changed) // 0 — нет, 1 — успех, -1 — ошибка
    Q_PROPERTY(QString result READ result NOTIFY changed)
    Q_PROPERTY(QVariantList objects READ objects NOTIFY changed)
    Q_PROPERTY(bool loggedIn READ loggedIn NOTIFY changed)
    Q_PROPERTY(qulonglong loggedInSlot READ loggedInSlot NOTIFY changed)

public:
    explicit TokenSession(QObject *parent = nullptr);

    bool busy() const { return m_busy; }
    int outcome() const { return m_outcome; }
    QString result() const { return m_result; }
    QVariantList objects() const { return m_objects; }
    bool loggedIn() const { return m_loggedIn; }
    qulonglong loggedInSlot() const { return m_cachedSlot; }

    // Вход по PIN + чтение всех объектов (сертификаты и ключи). При успехе PIN
    // запоминается (loggedIn=true) для последующих операций без повторного ввода.
    Q_INVOKABLE void login(qulonglong slotId, const QString &pin);
    // Чтение только сертификатов без входа (они видны без PIN).
    Q_INVOKABLE void preview(qulonglong slotId);
    // Сброс запомненного входа (кнопка «Разлогиниться»): обнуляет PIN и объекты.
    Q_INVOKABLE void logout();
    // Генерация ключевой пары на токене (вход по PIN, R/W-сессия, C_GenerateKeyPair),
    // затем перечитывание объектов. algorithm: "gost256"/"gost512"/"rsa2048"/"rsa4096".
    Q_INVOKABLE void generateKeyPair(qulonglong slotId, const QString &pin,
                                     const QString &algorithm, const QString &label);
    // То же с запомненным PIN (USB, после login на этом же слоте).
    Q_INVOKABLE void generateKeyPairCached(qulonglong slotId, const QString &algorithm,
                                           const QString &label);
    // Импорт X.509-сертификата из файла на токен (вход по PIN, R/W-сессия,
    // C_CreateObject) с приклеиванием к ключевой паре по открытому ключу; затем
    // перечитывание объектов.
    Q_INVOKABLE void importCertificate(qulonglong slotId, const QString &pin,
                                       const QString &filePath, const QString &label);
    // То же с запомненным PIN (USB, после login на этом же слоте).
    Q_INVOKABLE void importCertificateCached(qulonglong slotId, const QString &filePath,
                                             const QString &label);
    // Сбросить запомненный вход, если слот больше не присутствует среди tokens
    // (отключение USB-токена). Вызывается при изменении списка TokenWatcher.
    Q_INVOKABLE void retainUsbSlot(const QVariantList &tokens);
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

    // Запомненный вход (USB). PIN хранится в UTF-8 и обнуляется при сбросе.
    QByteArray m_cachedPin;
    qulonglong m_cachedSlot = 0;
    bool m_loggedIn = false;
    // Ожидающий вход: PIN кэшируется только при успехе (проверяется в onFinished).
    QByteArray m_pendingPin;
    qulonglong m_pendingSlot = 0;
    bool m_pendingIsLogin = false;
};

#endif // TOKENSESSION_H
