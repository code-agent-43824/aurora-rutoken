#ifndef DIAGNOSTICS_H
#define DIAGNOSTICS_H

#include <QtCore/QObject>
#include <QtCore/QVariantList>

// Диагностика v0.0.2: достижимость PC/SC (libpcsclite + pcscd) и NFC-стека
// (nfcd через системную D-Bus-шину). PC/SC грузится через dlopen, чтобы
// приложение стартовало и на системе без библиотеки; сами вызовы PC/SC
// выполняются в рабочем потоке (могут блокироваться на сокете pcscd).
class Diagnostics : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QVariantList rows READ rows NOTIFY rowsChanged)

public:
    explicit Diagnostics(QObject *parent = nullptr);

    bool running() const { return m_running; }
    QVariantList rows() const { return m_rows; }

    Q_INVOKABLE void refresh();

signals:
    void runningChanged();
    void rowsChanged();
    void pcscRowsReady(const QVariantList &pcscRows); // из рабочего потока

private:
    void probePcsc();                 // рабочий поток
    QVariantList probeNfc() const;    // главный поток (QtDBus)

    bool m_running = false;
    QVariantList m_rows;
    QVariantList m_nfcRows;
};

#endif // DIAGNOSTICS_H
