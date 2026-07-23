#include "pkcs11_errors.h"

namespace {

// Текст для распространённых кодов PKCS#11 v2.40 (значения фиксированы стандартом).
const char *rvText(unsigned long rv)
{
    switch (rv) {
    case 0x00000000UL: return "успех";
    case 0x00000001UL: return "операция отменена";
    case 0x00000002UL: return "недостаточно памяти хоста";
    // Слот пропал — как правило, токен убран/отключён. Даём подсказку к действию.
    case 0x00000003UL: return "слот недоступен — подключите токен заново и повторите";
    case 0x00000005UL: return "общая ошибка";
    case 0x00000006UL: return "функция завершилась с ошибкой";
    case 0x00000007UL: return "неверные аргументы";
    case 0x00000010UL: return "атрибут только для чтения";
    case 0x00000011UL: return "атрибут чувствителен (не читается)";
    case 0x00000012UL: return "неверный тип атрибута";
    case 0x00000013UL: return "недопустимое значение атрибута";
    case 0x00000020UL: return "недопустимые данные";
    case 0x00000021UL: return "недопустимая длина данных";
    case 0x00000030UL: return "ошибка устройства — переподключите токен и повторите";
    case 0x00000031UL: return "недостаточно памяти на токене";
    case 0x00000032UL: return "токен убран во время операции — повторите, удерживая токен на связи";
    case 0x00000050UL: return "операция отменена функцией";
    case 0x00000054UL: return "функция не поддерживается";
    case 0x00000060UL: return "неверный дескриптор ключа";
    case 0x00000062UL: return "недопустимый размер ключа";
    case 0x00000063UL: return "тип ключа не соответствует механизму";
    case 0x00000068UL: return "операция не разрешена для этого ключа";
    case 0x0000006AUL: return "ключ неизвлекаем";
    case 0x00000070UL: return "неверный механизм";
    case 0x00000071UL: return "неверные параметры механизма";
    case 0x00000082UL: return "неверный дескриптор объекта";
    case 0x00000090UL: return "уже идёт другая операция";
    case 0x00000091UL: return "операция не инициализирована";
    case 0x000000A0UL: return "неверный PIN-код";
    case 0x000000A1UL: return "недопустимый PIN-код";
    case 0x000000A2UL: return "недопустимая длина PIN-кода";
    case 0x000000A3UL: return "PIN-код просрочен";
    case 0x000000A4UL: return "PIN-код заблокирован";
    case 0x000000B0UL: return "сессия прервана (возможно, токен убран) — повторите";
    case 0x000000B1UL: return "слишком много открытых сессий";
    case 0x000000B3UL: return "сессия прервана (возможно, токен убран) — повторите";
    case 0x000000B5UL: return "сессия только для чтения";
    case 0x000000C0UL: return "подпись недействительна";
    case 0x000000C1UL: return "недопустимая длина подписи";
    case 0x000000D0UL: return "шаблон неполон";
    case 0x000000D1UL: return "противоречивый шаблон";
    case 0x000000E0UL: return "токен не подключён — подключите токен и повторите";
    case 0x000000E1UL: return "токен не распознан";
    case 0x000000E2UL: return "токен защищён от записи";
    case 0x00000100UL: return "пользователь уже вошёл";
    case 0x00000101UL: return "нужен вход по PIN-коду";
    case 0x00000102UL: return "PIN-код пользователя не задан";
    case 0x00000103UL: return "неверный тип пользователя";
    case 0x00000150UL: return "буфер слишком мал";
    case 0x00000190UL: return "Cryptoki не инициализирован";
    case 0x00000191UL: return "Cryptoki уже инициализирован";
    case 0x00000200UL: return "функция отклонена";
    default: return nullptr;
    }
}

} // namespace

namespace pkcs11 {

QString rvMessage(unsigned long rv)
{
    const QString hex = QStringLiteral("0x%1").arg(rv, 8, 16, QLatin1Char('0'));
    const char *t = rvText(rv);
    if (t)
        return QString::fromUtf8(t) + QStringLiteral(" (") + hex + QLatin1Char(')');
    return QStringLiteral("код ") + hex;
}

} // namespace pkcs11
