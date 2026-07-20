#ifndef PKCS11_OBJECTS_H
#define PKCS11_OBJECTS_H

#include <QtCore/QVariantList>

struct CK_FUNCTION_LIST_PREFIX;

namespace pkcs11 {

// Двухуровневая структура объектов токена:
//  - верхний уровень: сертификаты (kind="certificate") с вложенным списком
//    keys (ключи с тем же CKA_ID) и флагом hasKey;
//  - ключи, у которых нет сертификата с совпадающим CKA_ID, тоже попадают на
//    верхний уровень (kind="key") с CKA_ID и CKA_LABEL.
// Каждый элемент несёт source="PKCS#11" (пока единственный способ чтения).
// Сессия должна быть открыта и, для приватных ключей, залогинена.
QVariantList listTokenObjects(CK_FUNCTION_LIST_PREFIX *functions, unsigned long session);

} // namespace pkcs11

#endif // PKCS11_OBJECTS_H
