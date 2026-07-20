// Minimal PKCS#11 v2.40 ABI declarations needed by diagnostics.cpp.
//
// The declarations follow the functionally equivalent public-domain headers
// maintained by Latchset:
// https://github.com/latchset/pkcs11-headers/tree/main/public-domain/2.40
// Only the prefix of CK_FUNCTION_LIST up to C_GetTokenInfo is retained here,
// together with the CK_INFO / CK_SLOT_INFO / CK_TOKEN_INFO structures.
//
// ВАЖНО (урок краша v0.0.3-1 на телефоне): однобайтовая упаковка структур
// (#pragma pack(1)) — требование PKCS#11 ТОЛЬКО для Windows. На Linux
// (и Авроре) библиотеки, включая librtpkcs11ecp.so, собираются с естественным
// выравниванием. pack(1) смещал указатели в CK_FUNCTION_LIST (вызов мусорного
// адреса → SIGSEGV) и укорачивал CK_INFO (запись за границу буфера). Никакого
// pack на Linux быть не должно; раскладку проверяют static_assert ниже для
// обеих архитектур Авроры (armv7hl — ILP32, aarch64 — LP64).

#ifndef PKCS11_MINIMAL_H
#define PKCS11_MINIMAL_H

#include <cstddef>

typedef unsigned char CK_BYTE;
typedef unsigned char CK_BBOOL;
typedef unsigned char CK_CHAR;
typedef unsigned char CK_UTF8CHAR;
typedef unsigned long CK_ULONG;
typedef CK_ULONG CK_FLAGS;
typedef CK_ULONG CK_RV;
typedef CK_ULONG CK_SLOT_ID;
typedef CK_ULONG CK_SESSION_HANDLE;
typedef CK_ULONG CK_USER_TYPE;
typedef CK_ULONG CK_OBJECT_HANDLE;
typedef CK_ULONG CK_OBJECT_CLASS;
typedef CK_ULONG CK_KEY_TYPE;
typedef CK_ULONG CK_ATTRIBUTE_TYPE;
typedef void *CK_VOID_PTR;

static const CK_ULONG CK_UNAVAILABLE_INFORMATION = static_cast<CK_ULONG>(-1);

static const CK_BBOOL CK_TRUE_VALUE = 1;

static const CK_RV CKR_OK = 0x00000000UL;
static const CK_RV CKR_CRYPTOKI_ALREADY_INITIALIZED = 0x00000191UL;
static const CK_RV CKR_BUFFER_TOO_SMALL = 0x00000150UL;
static const CK_RV CKR_PIN_INCORRECT = 0x000000A0UL;
static const CK_RV CKR_PIN_LOCKED = 0x000000A4UL;
static const CK_RV CKR_USER_ALREADY_LOGGED_IN = 0x00000100UL;
static const CK_RV CKR_USER_PIN_NOT_INITIALIZED = 0x00000102UL;

static const CK_USER_TYPE CKU_USER = 1;

// Флаги открытия сессии (C_OpenSession).
static const CK_FLAGS CKF_RW_SESSION = 0x00000002UL;
static const CK_FLAGS CKF_SERIAL_SESSION = 0x00000004UL;

// Флаги токена (CK_TOKEN_INFO.flags), которые показываем в UI.
static const CK_FLAGS CKF_RNG = 0x00000001UL;
static const CK_FLAGS CKF_WRITE_PROTECTED = 0x00000002UL;
static const CK_FLAGS CKF_LOGIN_REQUIRED = 0x00000004UL;
static const CK_FLAGS CKF_USER_PIN_INITIALIZED = 0x00000008UL;
static const CK_FLAGS CKF_TOKEN_INITIALIZED = 0x00000400UL;
// Флаги состояния PIN пользователя (обновляются после неудачного C_Login).
static const CK_FLAGS CKF_USER_PIN_COUNT_LOW = 0x00010000UL;
static const CK_FLAGS CKF_USER_PIN_FINAL_TRY = 0x00020000UL;
static const CK_FLAGS CKF_USER_PIN_LOCKED = 0x00040000UL;

// Флаги слота (CK_SLOT_INFO.flags).
static const CK_FLAGS CKF_TOKEN_PRESENT = 0x00000001UL;
static const CK_FLAGS CKF_HW_SLOT = 0x00000004UL;

// Классы объектов (CKA_CLASS) и атрибуты для перечисления объектов токена.
static const CK_OBJECT_CLASS CKO_CERTIFICATE = 0x00000001UL;
static const CK_OBJECT_CLASS CKO_PUBLIC_KEY = 0x00000002UL;
static const CK_OBJECT_CLASS CKO_PRIVATE_KEY = 0x00000003UL;

static const CK_ATTRIBUTE_TYPE CKA_CLASS = 0x00000000UL;
static const CK_ATTRIBUTE_TYPE CKA_LABEL = 0x00000003UL;
static const CK_ATTRIBUTE_TYPE CKA_KEY_TYPE = 0x00000100UL;
static const CK_ATTRIBUTE_TYPE CKA_ID = 0x00000102UL;

// Типы ключей (CKA_KEY_TYPE) — для человекочитаемого отображения.
static const CK_KEY_TYPE CKK_RSA = 0x00000000UL;
static const CK_KEY_TYPE CKK_EC = 0x00000003UL;
static const CK_KEY_TYPE CKK_GOSTR3410 = 0x00000030UL;
static const CK_KEY_TYPE CKK_GOSTR3410_512 = 0x00000032UL;

struct CK_VERSION {
    CK_BYTE major;
    CK_BYTE minor;
};

struct CK_INFO {
    CK_VERSION cryptokiVersion;
    CK_UTF8CHAR manufacturerID[32];
    CK_FLAGS flags;
    CK_UTF8CHAR libraryDescription[32];
    CK_VERSION libraryVersion;
};

struct CK_SLOT_INFO {
    CK_UTF8CHAR slotDescription[64];
    CK_UTF8CHAR manufacturerID[32];
    CK_FLAGS flags;
    CK_VERSION hardwareVersion;
    CK_VERSION firmwareVersion;
};

struct CK_TOKEN_INFO {
    CK_UTF8CHAR label[32];
    CK_UTF8CHAR manufacturerID[32];
    CK_UTF8CHAR model[16];
    CK_CHAR serialNumber[16];
    CK_FLAGS flags;
    CK_ULONG ulMaxSessionCount;
    CK_ULONG ulSessionCount;
    CK_ULONG ulMaxRwSessionCount;
    CK_ULONG ulRwSessionCount;
    CK_ULONG ulMaxPinLen;
    CK_ULONG ulMinPinLen;
    CK_ULONG ulTotalPublicMemory;
    CK_ULONG ulFreePublicMemory;
    CK_ULONG ulTotalPrivateMemory;
    CK_ULONG ulFreePrivateMemory;
    CK_VERSION hardwareVersion;
    CK_VERSION firmwareVersion;
    CK_CHAR utcTime[16];
};

// Дескриптор атрибута для C_GetAttributeValue/C_FindObjectsInit.
struct CK_ATTRIBUTE {
    CK_ATTRIBUTE_TYPE type;
    CK_VOID_PTR pValue;
    CK_ULONG ulValueLen;
};

struct CK_FUNCTION_LIST_PREFIX;
typedef CK_RV (*CK_C_Initialize)(CK_VOID_PTR);
typedef CK_RV (*CK_C_Finalize)(CK_VOID_PTR);
typedef CK_RV (*CK_C_GetInfo)(CK_INFO *);
typedef CK_RV (*CK_C_GetFunctionList)(CK_FUNCTION_LIST_PREFIX **);
typedef CK_RV (*CK_C_GetSlotList)(CK_BBOOL, CK_SLOT_ID *, CK_ULONG *);
typedef CK_RV (*CK_C_GetSlotInfo)(CK_SLOT_ID, CK_SLOT_INFO *);
typedef CK_RV (*CK_C_GetTokenInfo)(CK_SLOT_ID, CK_TOKEN_INFO *);
typedef CK_RV (*CK_C_OpenSession)(CK_SLOT_ID, CK_FLAGS, CK_VOID_PTR, CK_VOID_PTR, CK_SESSION_HANDLE *);
typedef CK_RV (*CK_C_CloseSession)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_Login)(CK_SESSION_HANDLE, CK_USER_TYPE, CK_UTF8CHAR *, CK_ULONG);
typedef CK_RV (*CK_C_Logout)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_GetAttributeValue)(CK_SESSION_HANDLE, CK_OBJECT_HANDLE, CK_ATTRIBUTE *, CK_ULONG);
typedef CK_RV (*CK_C_FindObjectsInit)(CK_SESSION_HANDLE, CK_ATTRIBUTE *, CK_ULONG);
typedef CK_RV (*CK_C_FindObjects)(CK_SESSION_HANDLE, CK_OBJECT_HANDLE *, CK_ULONG, CK_ULONG *);
typedef CK_RV (*CK_C_FindObjectsFinal)(CK_SESSION_HANDLE);
// Заглушка для точек входа PKCS#11, которые нам не нужны, но обязаны занимать
// свою позицию в таблице ради правильных смещений последующих функций.
typedef CK_RV (*CK_SkippedFn)(void);

// Реальный CK_FUNCTION_LIST продолжается остальными точками входа PKCS#11.
// Порядок функций фиксирован стандартом; нам нужен префикс до C_FindObjectsFinal (№29).
struct CK_FUNCTION_LIST_PREFIX {
    CK_VERSION version;
    CK_C_Initialize C_Initialize;             // 1
    CK_C_Finalize C_Finalize;                 // 2
    CK_C_GetInfo C_GetInfo;                   // 3
    CK_C_GetFunctionList C_GetFunctionList;   // 4
    CK_C_GetSlotList C_GetSlotList;           // 5
    CK_C_GetSlotInfo C_GetSlotInfo;           // 6
    CK_C_GetTokenInfo C_GetTokenInfo;         // 7
    CK_SkippedFn C_GetMechanismList;          // 8
    CK_SkippedFn C_GetMechanismInfo;          // 9
    CK_SkippedFn C_InitToken;                 // 10
    CK_SkippedFn C_InitPIN;                   // 11
    CK_SkippedFn C_SetPIN;                    // 12
    CK_C_OpenSession C_OpenSession;           // 13
    CK_C_CloseSession C_CloseSession;         // 14
    CK_SkippedFn C_CloseAllSessions;          // 15
    CK_SkippedFn C_GetSessionInfo;            // 16
    CK_SkippedFn C_GetOperationState;         // 17
    CK_SkippedFn C_SetOperationState;         // 18
    CK_C_Login C_Login;                       // 19
    CK_C_Logout C_Logout;                     // 20
    CK_SkippedFn C_CreateObject;              // 21
    CK_SkippedFn C_CopyObject;                // 22
    CK_SkippedFn C_DestroyObject;             // 23
    CK_SkippedFn C_GetObjectSize;             // 24
    CK_C_GetAttributeValue C_GetAttributeValue; // 25
    CK_SkippedFn C_SetAttributeValue;         // 26
    CK_C_FindObjectsInit C_FindObjectsInit;   // 27
    CK_C_FindObjects C_FindObjects;           // 28
    CK_C_FindObjectsFinal C_FindObjectsFinal; // 29
};

// Контроль естественного выравнивания на обеих архитектурах Авроры.
// armv7hl: CK_ULONG/void* = 4 байта; aarch64: 8 байт. Значения ниже верны для
// обоих случаев и проверяются компилятором каждой архитектуры в CI.
static_assert(sizeof(CK_VERSION) == 2, "PKCS#11 CK_VERSION ABI mismatch");

static_assert(offsetof(CK_INFO, manufacturerID) == 2, "CK_INFO.manufacturerID offset");
static_assert(offsetof(CK_INFO, flags) == (sizeof(CK_ULONG) == 8 ? 40 : 36),
              "CK_INFO.flags must follow natural alignment (no pack pragma)");
static_assert(offsetof(CK_INFO, libraryDescription) == (sizeof(CK_ULONG) == 8 ? 48 : 40),
              "CK_INFO.libraryDescription offset");
static_assert(sizeof(CK_INFO) == (sizeof(CK_ULONG) == 8 ? 88 : 76), "CK_INFO size");

static_assert(offsetof(CK_SLOT_INFO, flags) == 96, "CK_SLOT_INFO.flags offset");
static_assert(offsetof(CK_SLOT_INFO, hardwareVersion) == (sizeof(CK_ULONG) == 8 ? 104 : 100),
              "CK_SLOT_INFO.hardwareVersion offset");
static_assert(sizeof(CK_SLOT_INFO) == (sizeof(CK_ULONG) == 8 ? 112 : 104), "CK_SLOT_INFO size");

static_assert(offsetof(CK_TOKEN_INFO, flags) == 96, "CK_TOKEN_INFO.flags offset");
static_assert(offsetof(CK_TOKEN_INFO, ulFreePrivateMemory) == 96 + 10 * sizeof(CK_ULONG),
              "CK_TOKEN_INFO memory-counter block offset");
static_assert(offsetof(CK_TOKEN_INFO, hardwareVersion) == 96 + 11 * sizeof(CK_ULONG),
              "CK_TOKEN_INFO.hardwareVersion offset");
static_assert(offsetof(CK_TOKEN_INFO, utcTime) == (sizeof(CK_ULONG) == 8 ? 188 : 144),
              "CK_TOKEN_INFO.utcTime offset");
static_assert(sizeof(CK_TOKEN_INFO) == (sizeof(CK_ULONG) == 8 ? 208 : 160), "CK_TOKEN_INFO size");

static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_Initialize) == sizeof(void *),
              "CK_FUNCTION_LIST: C_Initialize must sit at pointer alignment");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_GetFunctionList) == 4 * sizeof(void *),
              "CK_FUNCTION_LIST: C_GetFunctionList offset");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_GetSlotList) == 5 * sizeof(void *),
              "CK_FUNCTION_LIST: C_GetSlotList offset");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_GetTokenInfo) == 7 * sizeof(void *),
              "CK_FUNCTION_LIST: C_GetTokenInfo offset");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_OpenSession) == 13 * sizeof(void *),
              "CK_FUNCTION_LIST: C_OpenSession offset");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_CloseSession) == 14 * sizeof(void *),
              "CK_FUNCTION_LIST: C_CloseSession offset");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_Login) == 19 * sizeof(void *),
              "CK_FUNCTION_LIST: C_Login offset");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_Logout) == 20 * sizeof(void *),
              "CK_FUNCTION_LIST: C_Logout offset");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_GetAttributeValue) == 25 * sizeof(void *),
              "CK_FUNCTION_LIST: C_GetAttributeValue offset");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_FindObjectsInit) == 27 * sizeof(void *),
              "CK_FUNCTION_LIST: C_FindObjectsInit offset");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_FindObjectsFinal) == 29 * sizeof(void *),
              "CK_FUNCTION_LIST: C_FindObjectsFinal offset");

static_assert(offsetof(CK_ATTRIBUTE, pValue) == sizeof(void *), "CK_ATTRIBUTE.pValue offset");
static_assert(offsetof(CK_ATTRIBUTE, ulValueLen) == 2 * sizeof(void *), "CK_ATTRIBUTE.ulValueLen offset");
static_assert(sizeof(CK_ATTRIBUTE) == 3 * sizeof(void *), "CK_ATTRIBUTE size");

#endif // PKCS11_MINIMAL_H
