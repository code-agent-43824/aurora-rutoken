#ifndef DIAGNOSTICS_H
#define DIAGNOSTICS_H

#include <QtCore/QObject>
#include <QtCore/QVariantList>
#include <QtCore/QStringList>

// Диагностика: NFC (nfcd), PC/SC (pcscd, ридеры) и официальный PKCS#11-модуль
// Рутокен (жизненный цикл: загрузка, C_Initialize/C_GetInfo/C_Finalize).
// Перечисление токенов вынесено на продуктовый экран (TokenWatcher). Версия
// приложения показывается в шапке экрана диагностики (appVersion). Динамическая
// загрузка сохраняет работоспособность экрана даже при отсутствии одной из
// библиотек. Потенциально блокирующие PC/SC/PKCS#11-вызовы — в рабочем потоке.
class Diagnostics : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QVariantList rows READ rows NOTIFY rowsChanged)
    Q_PROPERTY(bool cryptoProEnabled READ cryptoProEnabled WRITE setCryptoProEnabled
               NOTIFY cryptoProEnabledChanged)

public:
    explicit Diagnostics(QObject *parent = nullptr);

    bool running() const { return m_running; }
    QVariantList rows() const { return m_rows; }
    bool cryptoProEnabled() const { return m_cryptoProEnabled; }

    void setCryptoProEnabled(bool enabled);
    void setCryptoProLibraries(const QStringList &paths);
    Q_INVOKABLE void refresh();

signals:
    void runningChanged();
    void rowsChanged();
    void cryptoProEnabledChanged();
    void backendRowsReady(const QVariantList &backendRows); // из рабочего потока

private:
    void probeBackends(bool includeCryptoPro,
                       const QStringList &cryptoProLibraries); // рабочий поток
    QVariantList probePcsc() const;
    QVariantList probePkcs11() const;
    QVariantList probeCryptoProLibraries(const QStringList &paths) const;
    QVariantList probeNfc() const;        // главный поток (QtDBus)

    bool m_running = false;
    QVariantList m_rows;
    QVariantList m_nfcRows;
    bool m_cryptoProEnabled = false;
    QStringList m_cryptoProLibraries;
};

#endif // DIAGNOSTICS_H
