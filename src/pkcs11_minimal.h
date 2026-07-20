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
typedef void *CK_VOID_PTR;

static const CK_BBOOL CK_TRUE_VALUE = 1;

static const CK_RV CKR_OK = 0x00000000UL;
static const CK_RV CKR_CRYPTOKI_ALREADY_INITIALIZED = 0x00000191UL;
static const CK_RV CKR_BUFFER_TOO_SMALL = 0x00000150UL;

// Флаги токена (CK_TOKEN_INFO.flags), которые показываем в UI.
static const CK_FLAGS CKF_RNG = 0x00000001UL;
static const CK_FLAGS CKF_WRITE_PROTECTED = 0x00000002UL;
static const CK_FLAGS CKF_LOGIN_REQUIRED = 0x00000004UL;
static const CK_FLAGS CKF_USER_PIN_INITIALIZED = 0x00000008UL;
static const CK_FLAGS CKF_TOKEN_INITIALIZED = 0x00000400UL;

// Флаги слота (CK_SLOT_INFO.flags).
static const CK_FLAGS CKF_TOKEN_PRESENT = 0x00000001UL;
static const CK_FLAGS CKF_HW_SLOT = 0x00000004UL;

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

struct CK_FUNCTION_LIST_PREFIX;
typedef CK_RV (*CK_C_Initialize)(CK_VOID_PTR);
typedef CK_RV (*CK_C_Finalize)(CK_VOID_PTR);
typedef CK_RV (*CK_C_GetInfo)(CK_INFO *);
typedef CK_RV (*CK_C_GetFunctionList)(CK_FUNCTION_LIST_PREFIX **);
typedef CK_RV (*CK_C_GetSlotList)(CK_BBOOL, CK_SLOT_ID *, CK_ULONG *);
typedef CK_RV (*CK_C_GetSlotInfo)(CK_SLOT_ID, CK_SLOT_INFO *);
typedef CK_RV (*CK_C_GetTokenInfo)(CK_SLOT_ID, CK_TOKEN_INFO *);

// Реальный CK_FUNCTION_LIST продолжается остальными точками входа PKCS#11.
// Порядок функций фиксирован стандартом; нам нужен префикс до C_GetTokenInfo.
struct CK_FUNCTION_LIST_PREFIX {
    CK_VERSION version;
    CK_C_Initialize C_Initialize;
    CK_C_Finalize C_Finalize;
    CK_C_GetInfo C_GetInfo;
    CK_C_GetFunctionList C_GetFunctionList;
    CK_C_GetSlotList C_GetSlotList;
    CK_C_GetSlotInfo C_GetSlotInfo;
    CK_C_GetTokenInfo C_GetTokenInfo;
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

#endif // PKCS11_MINIMAL_H
