#ifndef TOKENSESSION_H
#define TOKENSESSION_H

#include <QtCore/QByteArray>
#include <QtCore/QObject>
#include <QtCore/QLibrary>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>

// Проверка PIN пользователя на конкретном слоте. Операция выполняется одним
// изолированным циклом в рабочем потоке под общим мьютексом PKCS#11:
// C_Initialize → C_OpenSession → C_Login → [C_GetTokenInfo для флагов] →
// C_Logout → C_CloseSession → C_Finalize.
//
// Запоминание PIN (для USB): после успешного login() PIN хранится в оперативной
// памяти (m_cachedPin) и переиспользуется генерацией/импортом без повторного
// ввода — до logout(), отключения слота (syncWithTokens) или закрытия приложения.
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
    // Логически подключённый NFC-токен и его снимок объектов (см. ниже).
    Q_PROPERTY(QVariantMap nfcToken READ nfcToken NOTIFY changed)
    Q_PROPERTY(QVariantList nfcObjects READ nfcObjects NOTIFY changed)
    Q_PROPERTY(bool nfcConnected READ nfcConnected NOTIFY changed)
    // Серийники USB-токенов, логически отключённых (скрыты из списка).
    Q_PROPERTY(QStringList suppressedUsb READ suppressedUsb NOTIFY changed)

public:
    explicit TokenSession(QObject *parent = nullptr);

    bool busy() const { return m_busy; }
    int outcome() const { return m_outcome; }
    QString result() const { return m_result; }
    QVariantList objects() const { return m_objects; }
    bool loggedIn() const { return m_loggedIn; }
    qulonglong loggedInSlot() const { return m_cachedSlot; }
    QVariantMap nfcToken() const { return m_nfcToken; }
    QVariantList nfcObjects() const { return m_nfcObjects; }
    bool nfcConnected() const { return !m_nfcToken.isEmpty(); }
    QStringList suppressedUsb() const { return m_suppressedUsb; }

    // Вход по PIN + чтение всех объектов (сертификаты и ключи). При успехе PIN
    // запоминается (loggedIn=true) для последующих операций без повторного ввода.
    Q_INVOKABLE void login(qulonglong slotId, const QString &pin);
    // Чтение только сертификатов без входа (они видны без PIN).
    Q_INVOKABLE void preview(qulonglong slotId);
    // Вход по PIN + чтение всех объектов БЕЗ запоминания PIN — для NFC-подключения
    // (у NFC другая парадигма: PIN вводится в мастере на каждое подключение).
    Q_INVOKABLE void nfcRead(qulonglong slotId, const QString &pin);
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
    // Логически подключённый NFC-токен: снимок объектов сохраняется, чтобы
    // вернуться к его сертификатам без повторного поднесения.
    Q_INVOKABLE void commitNfc(const QVariantMap &token); // токен + снимок текущих объектов
    Q_INVOKABLE void updateNfcObjects();                  // обновить снимок после операции по NFC
    Q_INVOKABLE void disconnectNfc();                     // логически отключить NFC-токен
    // Логически отключить USB-токен: скрыть из списка до физического переподключения.
    Q_INVOKABLE void suppressUsb(const QString &serial);
    // Синхронизация со списком TokenWatcher: сброс входа при пропаже USB-слота и
    // снятие подавления с серийников, которых больше нет. Вызывается при изменении
    // списка TokenWatcher.
    Q_INVOKABLE void syncWithTokens(const QVariantList &tokens);
    Q_INVOKABLE void clear();

    // Управление PIN (v0.5), изолированный цикл под общим мьютексом:
    //  - смена PIN пользователя: C_SetPIN(old,new) в R/W-сессии;
    //  - смена PIN администратора (SO): C_Login(SO,old) → C_SetPIN(old,new) → C_Logout;
    //  - разблокировка PIN пользователя: C_Login(SO) → C_InitPIN(newUser) → C_Logout.
    // Успешная смена/сброс пользовательского PIN сбрасывает запомненный вход.
    Q_INVOKABLE void changeUserPin(qulonglong slotId, const QString &oldPin, const QString &newPin);
    Q_INVOKABLE void changeSoPin(qulonglong slotId, const QString &oldSoPin, const QString &newSoPin);
    Q_INVOKABLE void unblockUserPin(qulonglong slotId, const QString &soPin, const QString &newUserPin);

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

    // Логически подключённый NFC-токен: дескриптор и снимок объектов.
    QVariantMap m_nfcToken;
    QVariantList m_nfcObjects;
    // Серийники логически отключённых USB-токенов (скрыты до переподключения).
    QStringList m_suppressedUsb;
    // Текущая операция изменила пользовательский PIN → при успехе сбросить кэш входа.
    bool m_invalidateUserPin = false;
};

#endif // TOKENSESSION_H
