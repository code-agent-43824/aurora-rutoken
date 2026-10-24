#ifndef PKCS11_OBJECTS_H
#define PKCS11_OBJECTS_H

#include <QtCore/QByteArray>
#include <QtCore/QVariantList>

struct CK_FUNCTION_LIST_PREFIX;

namespace pkcs11 {

// Двухуровневая структура объектов токена:
//  - верхний уровень: сертификаты (kind="certificate"); описание берётся из
//    разобранного тела X.509 (commonName/issuer/expiry), с fallback на CKA_LABEL;
//  - если loggedIn=true — под каждым сертификатом ключи его пары (совпадение
//    по CKA_ID; у пары может быть несколько сертификатов), флаг hasKey, а ключи
//    без сертификата попадают на верхний уровень (kind="key"); при
//    loggedIn=false ключи не читаются (приватные не видны без входа), у
//    сертификатов keysKnown=false.
// Точные копии сертификата (тот же DER и CKA_ID) дают одну строку.
// Каждый элемент несёт source="PKCS#11" (пока единственный способ чтения).
QVariantList listTokenObjects(CK_FUNCTION_LIST_PREFIX *functions, unsigned long session, bool loggedIn);

// Удалить объекты с заданным CKA_ID:
//  - certificateDer непустой — сертификаты этого CKA_ID с точно такими байтами
//    (все копии выбранного сертификата); другие сертификаты пары остаются;
//  - withKeys — также все объекты этого CKA_ID, кроме сертификатов (ключи).
// Пустой id или пустой запрос игнорируются (защита от массового удаления).
// Требует R/W-сессии; ключи — и входа. Возвращает число удалённых объектов.
int destroyObjects(CK_FUNCTION_LIST_PREFIX *functions, unsigned long session,
                   const QByteArray &idBytes, const QByteArray &certificateDer, bool withKeys);

} // namespace pkcs11

#endif // PKCS11_OBJECTS_H
