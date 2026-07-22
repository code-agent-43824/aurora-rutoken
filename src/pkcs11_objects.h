#ifndef PKCS11_OBJECTS_H
#define PKCS11_OBJECTS_H

#include <QtCore/QByteArray>
#include <QtCore/QVariantList>

struct CK_FUNCTION_LIST_PREFIX;

namespace pkcs11 {

// Двухуровневая структура объектов токена:
//  - верхний уровень: сертификаты (kind="certificate"); описание берётся из
//    разобранного тела X.509 (commonName/issuer/expiry), с fallback на CKA_LABEL;
//  - если loggedIn=true — под сертификатом его ключи (совпадение по CKA_ID),
//    флаг hasKey, а ключи без сертификата попадают на верхний уровень
//    (kind="key"); при loggedIn=false ключи не читаются (приватные не видны без
//    входа), у сертификатов keysKnown=false.
// Каждый элемент несёт source="PKCS#11" (пока единственный способ чтения).
QVariantList listTokenObjects(CK_FUNCTION_LIST_PREFIX *functions, unsigned long session, bool loggedIn);

// Удалить все объекты с заданным CKA_ID (сертификат + его ключи по общему id) —
// «удаление записи целиком». Требует R/W-сессии и входа (приватные ключи). Пустой
// id игнорируется (защита от массового удаления). Возвращает число удалённых.
int destroyByCkaId(CK_FUNCTION_LIST_PREFIX *functions, unsigned long session, const QByteArray &idBytes);

} // namespace pkcs11

#endif // PKCS11_OBJECTS_H
