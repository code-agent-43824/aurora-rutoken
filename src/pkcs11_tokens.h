#ifndef PKCS11_TOKENS_H
#define PKCS11_TOKENS_H

#include <QtCore/QString>
#include <QtCore/QVariantList>

struct CK_FUNCTION_LIST_PREFIX;

namespace pkcs11 {

// Перечислить подключённые токены (слоты с присутствующим токеном) через уже
// полученную таблицу функций. Каждый элемент — QVariantMap с ключами:
// label, serial, model, manufacturer, connection ("USB"/"NFC"/""),
// slotName, slotId, firmware, hardware, flags, present.
// Модуль должен быть инициализирован (C_Initialize) вызывающей стороной.
QVariantList listConnectedTokens(CK_FUNCTION_LIST_PREFIX *functions);

// Эвристика типа подключения по имени PC/SC-слота (ридера).
QString connectionType(const QString &slotName);

} // namespace pkcs11

#endif // PKCS11_TOKENS_H
