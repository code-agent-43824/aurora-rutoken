#include "tokenwatcher.h"
#include "pkcs11_guard.h"
#include "pkcs11_minimal.h"
#include "pkcs11_tokens.h"

#include <QtConcurrent/QtConcurrent>
#include <QtCore/QMutex>
#include <QtCore/QStringList>
#include <QtCore/QTimer>

namespace {
const int kPollIntervalMs = 2000;
const QString kLibraryPath = QStringLiteral(
    "/usr/lib/3rdparty/ru.rutoken.librtpkcs11ecp/librtpkcs11ecp.so");

// Сигнатура набора токенов для сравнения (чтобы не обновлять UI без изменений).
// Метка входит в сигнатуру: её смена (C_EX_SetTokenName) должна обновлять список
// и детали, иначе набор считается неизменным и UI показывает старую метку.
QString signatureOf(const QVariantList &cards)
{
    QStringList parts;
    for (const QVariant &v : cards) {
        const QVariantMap m = v.toMap();
        parts << m.value(QStringLiteral("slotId")).toString()
                 + QLatin1Char('|') + m.value(QStringLiteral("serial")).toString()
                 + QLatin1Char('|') + m.value(QStringLiteral("connection")).toString()
                 + QLatin1Char('|') + m.value(QStringLiteral("label")).toString();
    }
    parts.sort();
    return parts.join(QLatin1Char(';'));
}
} // namespace

TokenWatcher::TokenWatcher(QObject *parent)
    : QObject(parent)
    , m_timer(new QTimer(this))
{
    m_timer->setInterval(kPollIntervalMs);
    connect(m_timer, &QTimer::timeout, this, &TokenWatcher::doPoll);
    connect(this, &TokenWatcher::polled, this, &TokenWatcher::onPolled);
}

TokenWatcher::~TokenWatcher()
{
    if (m_library.isLoaded())
        m_library.unload();
}

void TokenWatcher::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit statusChanged();
}

void TokenWatcher::start()
{
    if (!m_getFunctionList) {
        m_library.setFileName(kLibraryPath);
        if (!m_library.load()) {
            setStatus(QStringLiteral("Библиотека PKCS#11 Рутокен не найдена: ")
                      + m_library.errorString());
            return;
        }
        m_getFunctionList = m_library.resolve("C_GetFunctionList");
        if (!m_getFunctionList) {
            setStatus(QStringLiteral("В библиотеке нет C_GetFunctionList"));
            return;
        }
    }

    setStatus(QStringLiteral("Готово"));
    m_timer->start();
    doPoll();
}

void TokenWatcher::refresh()
{
    doPoll();
}

void TokenWatcher::doPoll()
{
    if (m_polling || !m_getFunctionList)
        return;
    m_polling = true;

    // Указатель на C_GetFunctionList стабилен после load; захватываем в рабочий
    // поток и делаем изолированный цикл init → перечисление → finalize.
    const QFunctionPointer getFunctionList = m_getFunctionList;
    QtConcurrent::run([this, getFunctionList]() {
        QVariantList cards;
        QString error;

        // Изолированный цикл init…finalize не должен пересекаться с логином.
        QMutexLocker locker(&pkcs11::globalMutex());

        typedef CK_RV (*GetListFn)(CK_FUNCTION_LIST_PREFIX **);
        GetListFn getList = reinterpret_cast<GetListFn>(getFunctionList);
        CK_FUNCTION_LIST_PREFIX *functions = nullptr;
        if (getList(&functions) != CKR_OK || !functions
                || !functions->C_Initialize || !functions->C_Finalize) {
            error = QStringLiteral("C_GetFunctionList не дал таблицу функций");
            emit polled(cards, error);
            return;
        }

        const CK_RV rv = functions->C_Initialize(nullptr);
        const bool owns = (rv == CKR_OK);
        if (!owns && rv != CKR_CRYPTOKI_ALREADY_INITIALIZED) {
            error = QStringLiteral("C_Initialize вернул 0x%1")
                        .arg(static_cast<qulonglong>(rv), 0, 16);
            emit polled(cards, error);
            return;
        }

        cards = pkcs11::listConnectedTokens(functions);

        if (owns)
            functions->C_Finalize(nullptr);

        emit polled(cards, error);
    });
}

void TokenWatcher::onPolled(const QVariantList &cards, const QString &error)
{
    m_polling = false;

    if (!error.isEmpty())
        setStatus(error);
    else
        setStatus(cards.isEmpty() ? QStringLiteral("Токен не подключён")
                                  : QStringLiteral("Подключено токенов: %1").arg(cards.size()));

    const QString signature = signatureOf(cards);
    if (signature == m_signature)
        return;
    m_signature = signature;
    m_tokens = cards;
    emit tokensChanged();
}
