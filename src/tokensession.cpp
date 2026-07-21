#include "tokensession.h"
#include "pkcs11_certimport.h"
#include "pkcs11_guard.h"
#include "pkcs11_keygen.h"
#include "pkcs11_minimal.h"
#include "pkcs11_objects.h"

#include <QtConcurrent/QtConcurrent>
#include <QtCore/QByteArray>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QMutex>
#include <QtCore/QPair>
#include <QtCore/QStandardPaths>
#include <QtCore/QStringList>

#include <cstring>
#include <functional>

namespace {
const QString kLibraryPath = QStringLiteral(
    "/usr/lib/3rdparty/ru.rutoken.librtpkcs11ecp/librtpkcs11ecp.so");

QString rvHex(CK_RV rv)
{
    return QStringLiteral("0x%1").arg(static_cast<qulonglong>(rv), 8, 16, QLatin1Char('0'));
}

// Человекочитаемое состояние PIN пользователя по флагам токена (fallback, если
// vendor-функция недоступна).
QString pinAttemptsHint(CK_FLAGS flags)
{
    if (flags & CKF_USER_PIN_LOCKED)
        return QStringLiteral("PIN заблокирован");
    if (flags & CKF_USER_PIN_FINAL_TRY)
        return QStringLiteral("последняя попытка");
    if (flags & CKF_USER_PIN_COUNT_LOW)
        return QStringLiteral("осталось мало попыток");
    return QString();
}

// Vendor-функции Рутокена (dlsym-указатели передаём как QFunctionPointer).
typedef CK_RV (*ExGetTokenInfoExtendedFn)(CK_SLOT_ID, void *);
typedef CK_RV (*ExSetTokenNameFn)(CK_SESSION_HANDLE, CK_UTF8CHAR *, CK_ULONG);

// Честный остаток попыток PIN пользователя через C_EX_GetTokenInfoExtended.
// Размер CK_TOKEN_INFO_EXTENDED различается по архитектурам, поэтому подбираем
// принятый размер probe'ом (верный размер → CKR_OK), а поля читаем по
// фиксированным смещениям CK_ULONG: индекс 12 — max, 13 — осталось.
bool exUserPinRetries(ExGetTokenInfoExtendedFn fn, CK_SLOT_ID slot, CK_ULONG &left, CK_ULONG &maxCount)
{
    if (!fn)
        return false;
    unsigned char buf[320];
    for (CK_ULONG sz = 14 * sizeof(CK_ULONG); sz <= 256; sz += sizeof(CK_ULONG)) {
        std::memset(buf, 0, sizeof(buf));
        *reinterpret_cast<CK_ULONG *>(buf) = sz;
        if (fn(slot, buf) == CKR_OK) {
            maxCount = *reinterpret_cast<CK_ULONG *>(buf + 12 * sizeof(CK_ULONG));
            left = *reinterpret_cast<CK_ULONG *>(buf + 13 * sizeof(CK_ULONG));
            return true;
        }
    }
    return false;
}

// Сообщение об ошибке C_Login с честным остатком попыток (vendor), либо, если
// vendor-функция недоступна, качественным индикатором по флагам токена.
QString loginErrorMessage(CK_FUNCTION_LIST_PREFIX *fns, CK_SLOT_ID slotId, CK_RV rv,
                          ExGetTokenInfoExtendedFn exFn)
{
    QString hint;
    CK_ULONG left = 0, maxCount = 0;
    if (exUserPinRetries(exFn, slotId, left, maxCount)) {
        hint = maxCount > 0 ? QStringLiteral("осталось попыток: %1 из %2").arg(left).arg(maxCount)
                            : QStringLiteral("осталось попыток: %1").arg(left);
    } else if (fns->C_GetTokenInfo) {
        CK_TOKEN_INFO info;
        std::memset(&info, 0, sizeof(info));
        if (fns->C_GetTokenInfo(slotId, &info) == CKR_OK)
            hint = pinAttemptsHint(info.flags);
    }
    QString message;
    if (rv == CKR_PIN_INCORRECT)
        message = QStringLiteral("Неверный PIN");
    else if (rv == CKR_PIN_LOCKED)
        message = QStringLiteral("PIN заблокирован");
    else
        message = QStringLiteral("Ошибка входа: ") + rvHex(rv);
    if (!hint.isEmpty())
        message += QStringLiteral(" (") + hint + QLatin1Char(')');
    return message;
}

// Результат операции записи на токен для доставки в UI-поток.
struct WriteOutcome {
    int outcome = -1;
    QString message;
    QVariantList objects;
};

// Общий цикл записи на токен под общим мьютексом PKCS#11:
// C_Initialize → C_OpenSession(R/W) → C_Login(USER) → op → перечитывание
// объектов → C_Logout → C_CloseSession → C_Finalize. Операцию (генерация ключа,
// импорт сертификата) выполняет op в залогиненной сессии и возвращает (ok, msg).
// pinBytes обнуляется сразу после C_Login. Список объектов перечитывается всегда
// (и при неуспехе op — показать текущее состояние токена).
WriteOutcome runTokenWrite(QFunctionPointer getFunctionList, qulonglong slotId, QByteArray pinBytes,
                           QFunctionPointer exGetTokenInfoExtended,
                           const std::function<QPair<bool, QString>(CK_FUNCTION_LIST_PREFIX *, CK_SESSION_HANDLE)> &op)
{
    WriteOutcome wo;

    typedef CK_RV (*GetListFn)(CK_FUNCTION_LIST_PREFIX **);
    GetListFn getList = reinterpret_cast<GetListFn>(getFunctionList);
    CK_FUNCTION_LIST_PREFIX *fns = nullptr;

    QMutexLocker locker(&pkcs11::globalMutex());

    const bool haveFns = getList(&fns) == CKR_OK && fns && fns->C_Initialize
            && fns->C_Finalize && fns->C_OpenSession && fns->C_CloseSession
            && fns->C_Login && fns->C_Logout;
    if (!haveFns) {
        pinBytes.fill('\0');
        wo.message = QStringLiteral("Библиотека не предоставляет функции сессии");
        return wo;
    }

    const CK_RV initRv = fns->C_Initialize(nullptr);
    const bool owns = (initRv == CKR_OK);
    if (!owns && initRv != CKR_CRYPTOKI_ALREADY_INITIALIZED) {
        pinBytes.fill('\0');
        wo.message = QStringLiteral("C_Initialize: ") + rvHex(initRv);
        return wo;
    }

    // Запись объектов на токен требует R/W-сессии.
    CK_SESSION_HANDLE session = 0;
    CK_RV rv = fns->C_OpenSession(static_cast<CK_SLOT_ID>(slotId),
                                  CKF_SERIAL_SESSION | CKF_RW_SESSION, nullptr, nullptr, &session);
    if (rv != CKR_OK) {
        if (owns)
            fns->C_Finalize(nullptr);
        pinBytes.fill('\0');
        wo.message = QStringLiteral("Не удалось открыть R/W-сессию: ") + rvHex(rv);
        return wo;
    }

    rv = fns->C_Login(session, CKU_USER,
                      reinterpret_cast<CK_UTF8CHAR *>(pinBytes.data()),
                      static_cast<CK_ULONG>(pinBytes.size()));
    pinBytes.fill('\0');
    const bool loggedIn = (rv == CKR_OK || rv == CKR_USER_ALREADY_LOGGED_IN);
    if (!loggedIn) {
        wo.message = loginErrorMessage(fns, static_cast<CK_SLOT_ID>(slotId), rv,
                                       reinterpret_cast<ExGetTokenInfoExtendedFn>(exGetTokenInfoExtended));
        fns->C_CloseSession(session);
        if (owns)
            fns->C_Finalize(nullptr);
        return wo;
    }

    const QPair<bool, QString> r = op(fns, session);
    wo.outcome = r.first ? 1 : -1;
    wo.message = r.second;

    // Перечитываем объекты в той же залогиненной сессии — результат сразу виден.
    wo.objects = pkcs11::listTokenObjects(fns, session, /*loggedIn*/ true);

    fns->C_Logout(session);
    fns->C_CloseSession(session);
    if (owns)
        fns->C_Finalize(nullptr);
    return wo;
}

// Понятное сообщение по коду PIN-операции (смена/разблокировка).
QString pinRvMessage(CK_RV rv)
{
    switch (rv) {
    case CKR_PIN_INCORRECT: return QStringLiteral("Неверный текущий PIN");
    case CKR_PIN_LOCKED: return QStringLiteral("PIN заблокирован");
    case CKR_PIN_INVALID: return QStringLiteral("Недопустимый PIN");
    case CKR_PIN_LEN_RANGE: return QStringLiteral("Недопустимая длина нового PIN");
    default: return QStringLiteral("Ошибка: ") + rvHex(rv);
    }
}

// Изолированный цикл операции в R/W-сессии БЕЗ входа/чтения объектов
// (для управления PIN): C_Initialize → C_OpenSession(R/W) → op → C_CloseSession
// → C_Finalize под общим мьютексом. Вход/смену PIN делает op и возвращает (ok, msg).
QPair<int, QString> runSessionOp(QFunctionPointer getFunctionList, qulonglong slotId,
                                 const std::function<QPair<bool, QString>(CK_FUNCTION_LIST_PREFIX *, CK_SESSION_HANDLE)> &op)
{
    typedef CK_RV (*GetListFn)(CK_FUNCTION_LIST_PREFIX **);
    GetListFn getList = reinterpret_cast<GetListFn>(getFunctionList);
    CK_FUNCTION_LIST_PREFIX *fns = nullptr;

    QMutexLocker locker(&pkcs11::globalMutex());

    const bool haveFns = getList(&fns) == CKR_OK && fns && fns->C_Initialize
            && fns->C_Finalize && fns->C_OpenSession && fns->C_CloseSession;
    if (!haveFns)
        return qMakePair(-1, QStringLiteral("Библиотека не предоставляет функции сессии"));

    const CK_RV initRv = fns->C_Initialize(nullptr);
    const bool owns = (initRv == CKR_OK);
    if (!owns && initRv != CKR_CRYPTOKI_ALREADY_INITIALIZED)
        return qMakePair(-1, QStringLiteral("C_Initialize: ") + rvHex(initRv));

    CK_SESSION_HANDLE session = 0;
    CK_RV rv = fns->C_OpenSession(static_cast<CK_SLOT_ID>(slotId),
                                  CKF_SERIAL_SESSION | CKF_RW_SESSION, nullptr, nullptr, &session);
    if (rv != CKR_OK) {
        if (owns)
            fns->C_Finalize(nullptr);
        return qMakePair(-1, QStringLiteral("Не удалось открыть R/W-сессию: ") + rvHex(rv));
    }

    const QPair<bool, QString> r = op(fns, session);

    fns->C_CloseSession(session);
    if (owns)
        fns->C_Finalize(nullptr);
    return qMakePair(r.first ? 1 : -1, r.second);
}
} // namespace

TokenSession::TokenSession(QObject *parent)
    : QObject(parent)
{
    connect(this, &TokenSession::finished, this, &TokenSession::onFinished);

    m_library.setFileName(kLibraryPath);
    if (m_library.load()) {
        m_getFunctionList = m_library.resolve("C_GetFunctionList");
        // Vendor-функции Рутокена экспортируются напрямую; их отсутствие не критично.
        m_exGetTokenInfoExtended = m_library.resolve("C_EX_GetTokenInfoExtended");
        m_exSetTokenName = m_library.resolve("C_EX_SetTokenName");
    }
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
    if (m_busy)
        return;
    // Запоминаем PIN как ожидающий; onFinished закэширует его только при успехе.
    m_pendingPin = pin.toUtf8();
    m_pendingSlot = slotId;
    m_pendingIsLogin = true;
    run(slotId, pin, /*doLogin*/ true);
}

void TokenSession::preview(qulonglong slotId)
{
    m_pendingIsLogin = false;
    run(slotId, QString(), /*doLogin*/ false);
}

void TokenSession::nfcRead(qulonglong slotId, const QString &pin)
{
    m_pendingIsLogin = false; // NFC не запоминает PIN
    run(slotId, pin, /*doLogin*/ true);
}

void TokenSession::logout()
{
    if (m_busy)
        return;
    m_cachedPin.fill('\0');
    m_cachedPin.clear();
    m_cachedSlot = 0;
    m_loggedIn = false;
    m_outcome = 0;
    m_result.clear();
    m_objects.clear();
    emit changed();
}

void TokenSession::generateKeyPairCached(qulonglong slotId, const QString &algorithm,
                                         const QString &label)
{
    if (!m_loggedIn || m_cachedSlot != slotId || m_cachedPin.isEmpty()) {
        m_outcome = -1;
        m_result = QStringLiteral("Сначала войдите по PIN");
        emit changed();
        return;
    }
    generateKeyPair(slotId, QString::fromUtf8(m_cachedPin.constData(), m_cachedPin.size()), algorithm, label);
}

void TokenSession::importCertificateCached(qulonglong slotId, const QString &filePath,
                                           const QString &label)
{
    if (!m_loggedIn || m_cachedSlot != slotId || m_cachedPin.isEmpty()) {
        m_outcome = -1;
        m_result = QStringLiteral("Сначала войдите по PIN");
        emit changed();
        return;
    }
    importCertificate(slotId, QString::fromUtf8(m_cachedPin.constData(), m_cachedPin.size()), filePath, label);
}

void TokenSession::syncWithTokens(const QVariantList &tokens)
{
    // 1) Сброс запомненного входа при пропаже залогиненного USB-слота.
    if (m_loggedIn && !m_busy) {
        bool present = false;
        for (int i = 0; i < tokens.size(); ++i) {
            if (tokens.at(i).toMap().value(QStringLiteral("slotId")).toULongLong() == m_cachedSlot) {
                present = true;
                break;
            }
        }
        if (!present)
            logout();
    }

    // 2) Снятие подавления с USB-токенов, которых больше нет (физически отключены)
    //    — чтобы после переподключения токен снова появился в списке.
    if (!m_suppressedUsb.isEmpty()) {
        QStringList presentSerials;
        for (int i = 0; i < tokens.size(); ++i)
            presentSerials << tokens.at(i).toMap().value(QStringLiteral("serial")).toString();
        bool pruned = false;
        for (int i = m_suppressedUsb.size() - 1; i >= 0; --i) {
            if (!presentSerials.contains(m_suppressedUsb.at(i))) {
                m_suppressedUsb.removeAt(i);
                pruned = true;
            }
        }
        if (pruned)
            emit changed();
    }
}

void TokenSession::commitNfc(const QVariantMap &token)
{
    m_nfcToken = token;
    m_nfcObjects = m_objects; // снимок только что прочитанных объектов
    emit changed();
}

void TokenSession::updateNfcObjects()
{
    if (m_nfcToken.isEmpty())
        return;
    m_nfcObjects = m_objects;
    emit changed();
}

void TokenSession::disconnectNfc()
{
    m_nfcToken.clear();
    m_nfcObjects.clear();
    emit changed();
}

void TokenSession::suppressUsb(const QString &serial)
{
    if (serial.isEmpty() || m_suppressedUsb.contains(serial))
        return;
    m_suppressedUsb.append(serial);
    emit changed();
}

void TokenSession::changeUserPin(qulonglong slotId, const QString &oldPin, const QString &newPin)
{
    if (m_busy)
        return;
    if (!m_getFunctionList) {
        m_outcome = -1;
        m_result = QStringLiteral("Библиотека PKCS#11 Рутокен не загружена");
        emit changed();
        return;
    }
    m_pendingIsLogin = false;
    m_invalidateUserPin = true; // меняется PIN пользователя → сбросить кэш при успехе
    m_busy = true;
    m_outcome = 0;
    m_result.clear();
    emit changed();

    const QFunctionPointer getFunctionList = m_getFunctionList;
    QByteArray oldB = oldPin.toUtf8();
    QByteArray newB = newPin.toUtf8();
    const QVariantList keepObjects = m_objects;

    QtConcurrent::run([this, slotId, oldB, newB, getFunctionList, keepObjects]() mutable {
        const QPair<int, QString> r = runSessionOp(getFunctionList, slotId,
            [&oldB, &newB](CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE s) {
                // Рутокен требует вход пользователем перед сменой его PIN
                // (иначе C_SetPIN → CKR_USER_NOT_LOGGED_IN = 0x101).
                if (!fns->C_SetPIN || !fns->C_Login || !fns->C_Logout)
                    return qMakePair(false, QStringLiteral("Библиотека не предоставляет функции смены PIN"));
                const CK_RV lr = fns->C_Login(s, CKU_USER,
                        reinterpret_cast<CK_UTF8CHAR *>(oldB.data()), static_cast<CK_ULONG>(oldB.size()));
                if (lr != CKR_OK && lr != CKR_USER_ALREADY_LOGGED_IN)
                    return qMakePair(false, pinRvMessage(lr));
                const CK_RV rv = fns->C_SetPIN(s,
                        reinterpret_cast<CK_UTF8CHAR *>(oldB.data()), static_cast<CK_ULONG>(oldB.size()),
                        reinterpret_cast<CK_UTF8CHAR *>(newB.data()), static_cast<CK_ULONG>(newB.size()));
                fns->C_Logout(s);
                return qMakePair(rv == CKR_OK,
                                 rv == CKR_OK ? QStringLiteral("PIN пользователя изменён") : pinRvMessage(rv));
            });
        oldB.fill('\0');
        newB.fill('\0');
        emit finished(r.first, r.second, keepObjects);
    });
}

void TokenSession::changeSoPin(qulonglong slotId, const QString &oldSoPin, const QString &newSoPin)
{
    if (m_busy)
        return;
    if (!m_getFunctionList) {
        m_outcome = -1;
        m_result = QStringLiteral("Библиотека PKCS#11 Рутокен не загружена");
        emit changed();
        return;
    }
    m_pendingIsLogin = false;
    m_invalidateUserPin = false; // меняется PIN администратора → кэш пользователя не трогаем
    m_busy = true;
    m_outcome = 0;
    m_result.clear();
    emit changed();

    const QFunctionPointer getFunctionList = m_getFunctionList;
    QByteArray oldB = oldSoPin.toUtf8();
    QByteArray newB = newSoPin.toUtf8();
    const QVariantList keepObjects = m_objects;

    QtConcurrent::run([this, slotId, oldB, newB, getFunctionList, keepObjects]() mutable {
        const QPair<int, QString> r = runSessionOp(getFunctionList, slotId,
            [&oldB, &newB](CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE s) {
                if (!fns->C_Login || !fns->C_Logout || !fns->C_SetPIN)
                    return qMakePair(false, QStringLiteral("Библиотека не предоставляет функции SO"));
                const CK_RV lr = fns->C_Login(s, CKU_SO,
                        reinterpret_cast<CK_UTF8CHAR *>(oldB.data()), static_cast<CK_ULONG>(oldB.size()));
                if (lr != CKR_OK && lr != CKR_USER_ALREADY_LOGGED_IN)
                    return qMakePair(false, pinRvMessage(lr));
                const CK_RV rv = fns->C_SetPIN(s,
                        reinterpret_cast<CK_UTF8CHAR *>(oldB.data()), static_cast<CK_ULONG>(oldB.size()),
                        reinterpret_cast<CK_UTF8CHAR *>(newB.data()), static_cast<CK_ULONG>(newB.size()));
                fns->C_Logout(s);
                return qMakePair(rv == CKR_OK,
                                 rv == CKR_OK ? QStringLiteral("PIN администратора изменён") : pinRvMessage(rv));
            });
        oldB.fill('\0');
        newB.fill('\0');
        emit finished(r.first, r.second, keepObjects);
    });
}

void TokenSession::unblockUserPin(qulonglong slotId, const QString &soPin, const QString &newUserPin)
{
    if (m_busy)
        return;
    if (!m_getFunctionList) {
        m_outcome = -1;
        m_result = QStringLiteral("Библиотека PKCS#11 Рутокен не загружена");
        emit changed();
        return;
    }
    m_pendingIsLogin = false;
    m_invalidateUserPin = true; // PIN пользователя сбрасывается → сбросить кэш при успехе
    m_busy = true;
    m_outcome = 0;
    m_result.clear();
    emit changed();

    const QFunctionPointer getFunctionList = m_getFunctionList;
    QByteArray soB = soPin.toUtf8();
    QByteArray newB = newUserPin.toUtf8();
    const QVariantList keepObjects = m_objects;

    QtConcurrent::run([this, slotId, soB, newB, getFunctionList, keepObjects]() mutable {
        const QPair<int, QString> r = runSessionOp(getFunctionList, slotId,
            [&soB, &newB](CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE s) {
                if (!fns->C_Login || !fns->C_Logout || !fns->C_InitPIN)
                    return qMakePair(false, QStringLiteral("Библиотека не предоставляет C_InitPIN"));
                const CK_RV lr = fns->C_Login(s, CKU_SO,
                        reinterpret_cast<CK_UTF8CHAR *>(soB.data()), static_cast<CK_ULONG>(soB.size()));
                if (lr != CKR_OK && lr != CKR_USER_ALREADY_LOGGED_IN)
                    return qMakePair(false, pinRvMessage(lr));
                const CK_RV rv = fns->C_InitPIN(s,
                        reinterpret_cast<CK_UTF8CHAR *>(newB.data()), static_cast<CK_ULONG>(newB.size()));
                fns->C_Logout(s);
                return qMakePair(rv == CKR_OK,
                                 rv == CKR_OK ? QStringLiteral("PIN пользователя разблокирован") : pinRvMessage(rv));
            });
        soB.fill('\0');
        newB.fill('\0');
        emit finished(r.first, r.second, keepObjects);
    });
}

void TokenSession::changeTokenLabel(qulonglong slotId, const QString &adminPin, const QString &label)
{
    if (m_busy)
        return;
    if (!m_getFunctionList || !m_exSetTokenName) {
        m_outcome = -1;
        m_result = m_getFunctionList ? QStringLiteral("Библиотека не поддерживает смену метки токена")
                                     : QStringLiteral("Библиотека PKCS#11 Рутокен не загружена");
        emit changed();
        return;
    }
    m_pendingIsLogin = false;
    m_invalidateUserPin = false;
    m_busy = true;
    m_outcome = 0;
    m_result.clear();
    emit changed();

    const QFunctionPointer getFunctionList = m_getFunctionList;
    const QFunctionPointer exSetName = m_exSetTokenName;
    QByteArray pinB = adminPin.toUtf8();
    QByteArray labelB = label.toUtf8();
    const QVariantList keepObjects = m_objects;

    QtConcurrent::run([this, slotId, pinB, labelB, getFunctionList, exSetName, keepObjects]() mutable {
        const QPair<int, QString> r = runSessionOp(getFunctionList, slotId,
            [&pinB, &labelB, exSetName](CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE s) {
                ExSetTokenNameFn setName = reinterpret_cast<ExSetTokenNameFn>(exSetName);
                if (!setName || !fns->C_Login || !fns->C_Logout)
                    return qMakePair(false, QStringLiteral("Библиотека не предоставляет смену метки"));
                // Смена метки токена требует входа администратора (SO).
                const CK_RV lr = fns->C_Login(s, CKU_SO,
                        reinterpret_cast<CK_UTF8CHAR *>(pinB.data()), static_cast<CK_ULONG>(pinB.size()));
                if (lr != CKR_OK && lr != CKR_USER_ALREADY_LOGGED_IN)
                    return qMakePair(false, pinRvMessage(lr));
                const CK_RV rv = setName(s,
                        reinterpret_cast<CK_UTF8CHAR *>(labelB.data()), static_cast<CK_ULONG>(labelB.size()));
                fns->C_Logout(s);
                return qMakePair(rv == CKR_OK,
                                 rv == CKR_OK ? QStringLiteral("Метка токена изменена") : pinRvMessage(rv));
            });
        pinB.fill('\0');
        emit finished(r.first, r.second, keepObjects);
    });
}

void TokenSession::generateKeyPair(qulonglong slotId, const QString &pin,
                                   const QString &algorithm, const QString &label)
{
    if (m_busy)
        return;
    m_pendingIsLogin = false; // не вход — не кэшировать PIN по завершении
    if (!m_getFunctionList) {
        m_outcome = -1;
        m_result = QStringLiteral("Библиотека PKCS#11 Рутокен не загружена");
        emit changed();
        return;
    }

    m_busy = true;
    m_outcome = 0;
    m_result.clear();
    emit changed();

    const QFunctionPointer getFunctionList = m_getFunctionList;
    const QFunctionPointer exTok = m_exGetTokenInfoExtended;
    QByteArray pinBytes = pin.toUtf8();

    QtConcurrent::run([this, slotId, pinBytes, getFunctionList, exTok, algorithm, label]() mutable {
        const WriteOutcome wo = runTokenWrite(getFunctionList, slotId, pinBytes, exTok,
            [&algorithm, &label](CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE session) {
                if (!fns->C_GenerateKeyPair)
                    return qMakePair(false, QStringLiteral("Библиотека не предоставляет C_GenerateKeyPair"));
                const pkcs11::KeygenResult gen = pkcs11::generateKeyPair(fns, session, algorithm, label);
                return qMakePair(gen.ok, gen.message);
            });
        pinBytes.fill('\0');
        emit finished(wo.outcome, wo.message, wo.objects);
    });
}

void TokenSession::importCertificate(qulonglong slotId, const QString &pin,
                                     const QString &filePath, const QString &label)
{
    if (m_busy)
        return;
    m_pendingIsLogin = false; // не вход — не кэшировать PIN по завершении
    if (!m_getFunctionList) {
        m_outcome = -1;
        m_result = QStringLiteral("Библиотека PKCS#11 Рутокен не загружена");
        emit changed();
        return;
    }

    m_busy = true;
    m_outcome = 0;
    m_result.clear();
    emit changed();

    const QFunctionPointer getFunctionList = m_getFunctionList;
    const QFunctionPointer exTok = m_exGetTokenInfoExtended;
    QByteArray pinBytes = pin.toUtf8();

    QtConcurrent::run([this, slotId, pinBytes, getFunctionList, exTok, filePath, label]() mutable {
        const WriteOutcome wo = runTokenWrite(getFunctionList, slotId, pinBytes, exTok,
            [&filePath, &label](CK_FUNCTION_LIST_PREFIX *fns, CK_SESSION_HANDLE session) {
                if (!fns->C_CreateObject)
                    return qMakePair(false, QStringLiteral("Библиотека не предоставляет C_CreateObject"));
                const pkcs11::ImportResult imp =
                        pkcs11::importCertificateFromFile(fns, session, filePath, label);
                return qMakePair(imp.ok, imp.message);
            });
        pinBytes.fill('\0');
        emit finished(wo.outcome, wo.message, wo.objects);
    });
}

void TokenSession::run(qulonglong slotId, const QString &pin, bool doLogin)
{
    if (m_busy)
        return;
    if (!m_getFunctionList) {
        m_pendingIsLogin = false; // вход не состоится — не кэшировать
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
    const QFunctionPointer exTok = m_exGetTokenInfoExtended;
    QByteArray pinBytes = pin.toUtf8();

    QtConcurrent::run([this, slotId, pinBytes, getFunctionList, exTok, doLogin]() mutable {
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
                message = loginErrorMessage(fns, static_cast<CK_SLOT_ID>(slotId), rv,
                                            reinterpret_cast<ExGetTokenInfoExtendedFn>(exTok));
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

    // Кэшируем PIN только для успешного входа (login), не для генерации/импорта.
    if (m_pendingIsLogin) {
        if (outcome == 1) {
            m_cachedPin = m_pendingPin;
            m_cachedSlot = m_pendingSlot;
            m_loggedIn = true;
        }
        m_pendingPin.fill('\0');
        m_pendingPin.clear();
        m_pendingIsLogin = false;
    }

    // Успешная смена/сброс пользовательского PIN делает запомненный вход невалидным.
    if (m_invalidateUserPin) {
        m_invalidateUserPin = false;
        if (outcome == 1) {
            m_cachedPin.fill('\0');
            m_cachedPin.clear();
            m_cachedSlot = 0;
            m_loggedIn = false;
        }
    }

    emit changed();
}

QString TokenSession::defaultExportDir()
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (dir.isEmpty())
        dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (dir.isEmpty())
        dir = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    return dir;
}

QString TokenSession::exportCertificate(const QString &derB64, const QString &format,
                                        const QString &dirPath, const QString &baseName)
{
    const QByteArray der = QByteArray::fromBase64(derB64.toLatin1());
    if (der.isEmpty())
        return QStringLiteral("Экспорт: пустое тело сертификата");

    const bool pemFormat = format.compare(QStringLiteral("pem"), Qt::CaseInsensitive) == 0;
    const QString ext = pemFormat ? QStringLiteral(".pem") : QStringLiteral(".der");

    // Безопасное имя файла (без пути); убираем уже присутствующее расширение.
    QString safe;
    for (int i = 0; i < baseName.size(); ++i) {
        const QChar c = baseName.at(i);
        if (c.isLetterOrNumber() || c == QLatin1Char('.') || c == QLatin1Char('_')
                || c == QLatin1Char('-') || c == QLatin1Char(' '))
            safe.append(c);
    }
    safe = safe.trimmed();
    if (safe.endsWith(QStringLiteral(".pem"), Qt::CaseInsensitive)
            || safe.endsWith(QStringLiteral(".der"), Qt::CaseInsensitive))
        safe.chop(4);
    if (safe.isEmpty())
        safe = QStringLiteral("certificate");

    QString dir = dirPath.trimmed();
    if (dir.isEmpty())
        dir = defaultExportDir();
    QDir().mkpath(dir);

    const QString path = dir + QLatin1Char('/') + safe + ext;

    QByteArray payload;
    if (pemFormat) {
        // PEM формируем вручную (не через QSslCertificate) — работает и для ГОСТ.
        payload = "-----BEGIN CERTIFICATE-----\n";
        const QByteArray b64 = der.toBase64();
        for (int i = 0; i < b64.size(); i += 64)
            payload += b64.mid(i, 64) + '\n';
        payload += "-----END CERTIFICATE-----\n";
    } else {
        payload = der;
    }

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(payload) != payload.size())
        return QStringLiteral("Не удалось записать ") + path;
    file.close();

    return QStringLiteral("Сохранено: ") + path;
}
