#include "tokenwatcher.h"
#include "pkcs11_guard.h"
#include "pkcs11_minimal.h"
#include "pkcs11_tokens.h"

#include <QtConcurrent/QtConcurrent>
#include <QtCore/QCoreApplication>
#include <QtCore/QMutex>
#include <QtCore/QStringList>
#include <cstdio>

namespace {
const QString kLibraryPath = QStringLiteral(
    "/usr/lib/3rdparty/ru.rutoken.librtpkcs11ecp/librtpkcs11ecp.so");
const char kReadyMarker[] = "RUTOKEN_SLOT_EVENT_READY\n";
const char kEventMarker[] = "RUTOKEN_SLOT_EVENT:";
const int kMaxEventHelperOutput = 4096;

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
{
    m_eventHelper.setProcessChannelMode(QProcess::SeparateChannels);
    connect(&m_eventHelper, &QProcess::readyReadStandardOutput,
            this, &TokenWatcher::readEventHelperOutput);
    connect(&m_eventHelper, &QProcess::readyReadStandardError, this, [this]() {
        m_eventHelper.readAllStandardError();
    });
    connect(&m_eventHelper,
            static_cast<void (QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
            this, &TokenWatcher::eventHelperFinished);
    connect(&m_eventHelper, &QProcess::errorOccurred,
            this, &TokenWatcher::eventHelperError);
    connect(this, &TokenWatcher::snapshotReady,
            this, &TokenWatcher::onSnapshotReady);
}

TokenWatcher::~TokenWatcher()
{
    m_stopping = true;
    if (m_eventHelper.state() != QProcess::NotRunning) {
        m_eventHelper.kill();
        m_eventHelper.waitForFinished(1000);
    }
    m_snapshotFuture.waitForFinished();
    if (m_library.isLoaded())
        m_library.unload();
}

int TokenWatcher::runSlotEventHelper()
{
    QLibrary library(kLibraryPath);
    if (!library.load())
        return 2;

    CK_C_GetFunctionList getFunctionList =
            reinterpret_cast<CK_C_GetFunctionList>(library.resolve("C_GetFunctionList"));
    CK_FUNCTION_LIST_PREFIX *functions = nullptr;
    if (!getFunctionList || getFunctionList(&functions) != CKR_OK || !functions
            || !functions->C_Initialize || !functions->C_Finalize
            || !functions->C_WaitForSlotEvent)
        return 3;

    const CK_RV initializeRv = functions->C_Initialize(nullptr);
    if (initializeRv != CKR_OK
            && initializeRv != CKR_CRYPTOKI_ALREADY_INITIALIZED)
        return 4;

    std::fwrite(kReadyMarker, 1, sizeof(kReadyMarker) - 1, stdout);
    if (std::fflush(stdout) != 0)
        return 5;

    for (;;) {
        CK_SLOT_ID slot = 0;
        const CK_RV rv = functions->C_WaitForSlotEvent(0, &slot, nullptr);
        if (rv == CKR_OK) {
            const QByteArray line = QByteArray(kEventMarker)
                    + QByteArray::number(static_cast<qulonglong>(slot)) + '\n';
            std::fwrite(line.constData(), 1, static_cast<size_t>(line.size()), stdout);
            if (std::fflush(stdout) != 0)
                return 6;
            continue;
        }
        if (rv == CKR_CRYPTOKI_NOT_INITIALIZED)
            return 0;
        return rv == CKR_FUNCTION_NOT_SUPPORTED ? 7 : 8;
    }
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
            setStatus(QStringLiteral("Библиотека PKCS#11 Рутокен не найдена — установите "
                                     "официальный пакет ru.rutoken.librtpkcs11ecp (")
                      + m_library.errorString() + QLatin1Char(')'));
            return;
        }
        m_getFunctionList = m_library.resolve("C_GetFunctionList");
        if (!m_getFunctionList) {
            setStatus(QStringLiteral("В библиотеке нет C_GetFunctionList"));
            return;
        }
    }

    setStatus(QStringLiteral("Готово"));
    doSnapshot();
    startEventHelper();
}

void TokenWatcher::refresh()
{
    doSnapshot();
}

void TokenWatcher::startEventHelper()
{
    if (m_eventHelper.state() != QProcess::NotRunning || m_stopping)
        return;
    m_eventHelperOutput.clear();
    m_eventHelperReady = false;
    m_eventHelper.setProgram(QCoreApplication::applicationFilePath());
    m_eventHelper.setArguments(QStringList(
                                   QStringLiteral("--pkcs11-slot-event-helper")));
    m_eventHelper.start(QIODevice::ReadOnly);
}

void TokenWatcher::readEventHelperOutput()
{
    m_eventHelperOutput.append(m_eventHelper.readAllStandardOutput());
    if (m_eventHelperOutput.size() > kMaxEventHelperOutput) {
        m_eventHelper.kill();
        setStatus(QStringLiteral("Слишком большой ответ ожидания событий PKCS#11"));
        return;
    }

    int newline = -1;
    while ((newline = m_eventHelperOutput.indexOf('\n')) >= 0) {
        const QByteArray line = m_eventHelperOutput.left(newline + 1);
        m_eventHelperOutput.remove(0, newline + 1);
        if (line == QByteArray(kReadyMarker)) {
            m_eventHelperReady = true;
        } else if (line.startsWith(kEventMarker) && m_eventHelperReady) {
            doSnapshot();
        }
    }
}

void TokenWatcher::eventHelperFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    readEventHelperOutput();
    if (m_stopping)
        return;
    m_eventHelperReady = false;
    if (exitStatus == QProcess::NormalExit && exitCode == 7)
        setStatus(QStringLiteral("Библиотека PKCS#11 не поддерживает C_WaitForSlotEvent"));
    else
        setStatus(QStringLiteral("Ожидание событий PKCS#11 остановлено"));
}

void TokenWatcher::eventHelperError(QProcess::ProcessError error)
{
    if (m_stopping || error == QProcess::Crashed)
        return;
    setStatus(error == QProcess::FailedToStart
              ? QStringLiteral("Не удалось запустить ожидание событий PKCS#11")
              : QStringLiteral("Ошибка ожидания событий PKCS#11"));
}

void TokenWatcher::doSnapshot()
{
    if (!m_getFunctionList)
        return;
    if (m_snapshotRunning) {
        m_snapshotPending = true;
        return;
    }
    m_snapshotRunning = true;

    const QFunctionPointer getFunctionList = m_getFunctionList;
    m_snapshotFuture = QtConcurrent::run([this, getFunctionList]() {
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
            emit snapshotReady(cards, error);
            return;
        }

        const CK_RV rv = functions->C_Initialize(nullptr);
        const bool owns = (rv == CKR_OK);
        if (!owns && rv != CKR_CRYPTOKI_ALREADY_INITIALIZED) {
            error = QStringLiteral("C_Initialize вернул 0x%1")
                        .arg(static_cast<qulonglong>(rv), 0, 16);
            emit snapshotReady(cards, error);
            return;
        }

        cards = pkcs11::listConnectedTokens(functions);

        if (owns)
            functions->C_Finalize(nullptr);

        emit snapshotReady(cards, error);
    });
}

void TokenWatcher::onSnapshotReady(const QVariantList &cards, const QString &error)
{
    m_snapshotRunning = false;

    if (!error.isEmpty())
        setStatus(error);
    else
        setStatus(cards.isEmpty() ? QStringLiteral("Устройство Рутокен не подключено")
                                  : QStringLiteral("Подключено устройств: %1").arg(cards.size()));

    const QString signature = signatureOf(cards);
    if (signature != m_signature) {
        m_signature = signature;
        m_tokens = cards;
        emit tokensChanged();
    }

    if (m_snapshotPending) {
        m_snapshotPending = false;
        doSnapshot();
    }
}
