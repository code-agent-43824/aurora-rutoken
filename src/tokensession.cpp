#include "tokensession.h"
#include "pkcs11_guard.h"
#include "pkcs11_minimal.h"
#include "pkcs11_objects.h"

#include <QtConcurrent/QtConcurrent>
#include <QtCore/QByteArray>
#include <QtCore/QMutex>
#include <QtCore/QStringList>

#include <cstring>

namespace {
const QString kLibraryPath = QStringLiteral(
    "/usr/lib/3rdparty/ru.rutoken.librtpkcs11ecp/librtpkcs11ecp.so");

QString rvHex(CK_RV rv)
{
    return QStringLiteral("0x%1").arg(static_cast<qulonglong>(rv), 8, 16, QLatin1Char('0'));
}

// Человекочитаемое состояние PIN пользователя по флагам токена после ошибки.
QString pinAttemptsHint(CK_FLAGS flags)
{
    QStringList hints;
    if (flags & CKF_USER_PIN_LOCKED)
        hints << QStringLiteral("PIN заблокирован");
    else if (flags & CKF_USER_PIN_FINAL_TRY)
        hints << QStringLiteral("последняя попытка!");
    else if (flags & CKF_USER_PIN_COUNT_LOW)
        hints << QStringLiteral("осталось мало попыток");
    return hints.join(QString());
}
} // namespace

TokenSession::TokenSession(QObject *parent)
    : QObject(parent)
{
    connect(this, &TokenSession::finished, this, &TokenSession::onFinished);

    m_library.setFileName(kLibraryPath);
    if (m_library.load())
        m_getFunctionList = m_library.resolve("C_GetFunctionList");
}

void TokenSession::clear()
{
    if (m_busy)
        return;
    m_outcome = 0;
    m_result.clear();
    m_objects.clear();
    emit changed();
}

void TokenSession::login(qulonglong slotId, const QString &pin)
{
    run(slotId, pin, /*doLogin*/ true);
}

void TokenSession::preview(qulonglong slotId)
{
    run(slotId, QString(), /*doLogin*/ false);
}

void TokenSession::run(qulonglong slotId, const QString &pin, bool doLogin)
{
    if (m_busy)
        return;
    if (!m_getFunctionList) {
        if (doLogin) {
            m_outcome = -1;
            m_result = QStringLiteral("Библиотека PKCS#11 Рутокен не загружена");
            emit changed();
        }
        return;
    }

    m_busy = true;
    if (doLogin) {
        m_outcome = 0;
        m_result.clear();
    }
    emit changed();

    const QFunctionPointer getFunctionList = m_getFunctionList;
    QByteArray pinBytes = pin.toUtf8();

    QtConcurrent::run([this, slotId, pinBytes, getFunctionList, doLogin]() mutable {
        int outcome = doLogin ? -1 : 0;
        QString message;
        QVariantList objects;

        typedef CK_RV (*GetListFn)(CK_FUNCTION_LIST_PREFIX **);
        GetListFn getList = reinterpret_cast<GetListFn>(getFunctionList);
        CK_FUNCTION_LIST_PREFIX *fns = nullptr;

        QMutexLocker locker(&pkcs11::globalMutex());

        const bool haveBasics = getList(&fns) == CKR_OK && fns && fns->C_Initialize
                && fns->C_Finalize && fns->C_OpenSession && fns->C_CloseSession;
        const bool haveLogin = fns && fns->C_Login && fns->C_Logout;
        if (!haveBasics || (doLogin && !haveLogin)) {
            pinBytes.fill('\0');
            emit finished(doLogin ? -1 : 0,
                          doLogin ? QStringLiteral("Библиотека не предоставляет функции сессии") : QString(),
                          QVariantList());
            return;
        }

        const CK_RV initRv = fns->C_Initialize(nullptr);
        const bool owns = (initRv == CKR_OK);
        if (!owns && initRv != CKR_CRYPTOKI_ALREADY_INITIALIZED) {
            pinBytes.fill('\0');
            emit finished(doLogin ? -1 : 0,
                          doLogin ? QStringLiteral("C_Initialize: ") + rvHex(initRv) : QString(),
                          QVariantList());
            return;
        }

        CK_SESSION_HANDLE session = 0;
        CK_RV rv = fns->C_OpenSession(static_cast<CK_SLOT_ID>(slotId),
                                      CKF_SERIAL_SESSION, nullptr, nullptr, &session);
        if (rv != CKR_OK) {
            if (owns)
                fns->C_Finalize(nullptr);
            pinBytes.fill('\0');
            emit finished(doLogin ? -1 : 0,
                          doLogin ? QStringLiteral("Не удалось открыть сессию: ") + rvHex(rv) : QString(),
                          QVariantList());
            return;
        }

        bool loggedIn = false;
        if (doLogin) {
            rv = fns->C_Login(session, CKU_USER,
                              reinterpret_cast<CK_UTF8CHAR *>(pinBytes.data()),
                              static_cast<CK_ULONG>(pinBytes.size()));
            if (rv == CKR_OK || rv == CKR_USER_ALREADY_LOGGED_IN) {
                loggedIn = true;
                outcome = 1;
                message = QStringLiteral("PIN верный — вход выполнен");
            } else {
                QString hint;
                if (fns->C_GetTokenInfo) {
                    CK_TOKEN_INFO info;
                    std::memset(&info, 0, sizeof(info));
                    if (fns->C_GetTokenInfo(static_cast<CK_SLOT_ID>(slotId), &info) == CKR_OK)
                        hint = pinAttemptsHint(info.flags);
                }
                if (rv == CKR_PIN_INCORRECT)
                    message = QStringLiteral("Неверный PIN");
                else if (rv == CKR_PIN_LOCKED)
                    message = QStringLiteral("PIN заблокирован");
                else
                    message = QStringLiteral("Ошибка входа: ") + rvHex(rv);
                if (!hint.isEmpty())
                    message += QStringLiteral(" (") + hint + QLatin1Char(')');
            }
        }

        // Сертификаты видны без входа; ключи — только в залогиненной сессии.
        if (!doLogin || loggedIn)
            objects = pkcs11::listTokenObjects(fns, session, loggedIn);

        if (loggedIn)
            fns->C_Logout(session);
        fns->C_CloseSession(session);
        if (owns)
            fns->C_Finalize(nullptr);

        pinBytes.fill('\0');
        emit finished(outcome, message, objects);
    });
}

void TokenSession::onFinished(int outcome, const QString &message, const QVariantList &objects)
{
    m_busy = false;
    m_outcome = outcome;
    m_result = message;
    m_objects = objects;
    emit changed();
}
