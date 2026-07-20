// Minimal PKCS#11 v2.40 ABI declarations needed by diagnostics.cpp.
//
// The declarations follow the functionally equivalent public-domain headers
// maintained by Latchset:
// https://github.com/latchset/pkcs11-headers/tree/main/public-domain/2.40
// Only the C_GetFunctionList -> C_Initialize/C_Finalize/C_GetInfo prefix is
// retained here.
//
// ВАЖНО (урок краша v0.0.3-1 на телефоне): однобайтовая упаковка структур
// (#pragma pack(1)) — требование PKCS#11 ТОЛЬКО для Windows. На Linux
// (и Авроре) библиотеки, включая librtpkcs11ecp.so, собираются с естественным
// выравниванием. pack(1) здесь смещал указатели в CK_FUNCTION_LIST (вызов
// мусорного адреса → SIGSEGV) и делал CK_INFO короче реальной (запись за
// границу буфера). Никакого pack на Linux быть не должно.

#ifndef PKCS11_MINIMAL_H
#define PKCS11_MINIMAL_H

#include <cstddef>

typedef unsigned char CK_BYTE;
typedef unsigned char CK_UTF8CHAR;
typedef unsigned long CK_ULONG;
typedef CK_ULONG CK_FLAGS;
typedef CK_ULONG CK_RV;
typedef void *CK_VOID_PTR;

static const CK_RV CKR_OK = 0x00000000UL;
static const CK_RV CKR_CRYPTOKI_ALREADY_INITIALIZED = 0x00000191UL;

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

struct CK_FUNCTION_LIST_PREFIX;
typedef CK_RV (*CK_C_Initialize)(CK_VOID_PTR);
typedef CK_RV (*CK_C_Finalize)(CK_VOID_PTR);
typedef CK_RV (*CK_C_GetInfo)(CK_INFO *);
typedef CK_RV (*CK_C_GetFunctionList)(CK_FUNCTION_LIST_PREFIX **);

// The real CK_FUNCTION_LIST continues with all other PKCS#11 entry points.
// Accessing this ABI-compatible prefix is sufficient for the v0.0.3 probe.
struct CK_FUNCTION_LIST_PREFIX {
    CK_VERSION version;
    CK_C_Initialize C_Initialize;
    CK_C_Finalize C_Finalize;
    CK_C_GetInfo C_GetInfo;
    CK_C_GetFunctionList C_GetFunctionList;
};

// Контроль естественного выравнивания на обеих архитектурах Авроры.
// armv7hl: CK_ULONG/void* = 4 байта; aarch64: 8 байт. Смещения ниже
// вычислены для обоих случаев и проверяются компилятором каждой архитектуры
// в CI (32-битные значения — компилятором armv7hl).
static_assert(sizeof(CK_VERSION) == 2, "PKCS#11 CK_VERSION ABI mismatch");
static_assert(offsetof(CK_INFO, manufacturerID) == 2, "CK_INFO.manufacturerID offset");
static_assert(offsetof(CK_INFO, flags) == (sizeof(CK_ULONG) == 8 ? 40 : 36),
              "CK_INFO.flags must follow natural alignment (no pack pragma)");
static_assert(offsetof(CK_INFO, libraryDescription) == (sizeof(CK_ULONG) == 8 ? 48 : 40),
              "CK_INFO.libraryDescription offset");
static_assert(offsetof(CK_INFO, libraryVersion) == (sizeof(CK_ULONG) == 8 ? 80 : 72),
              "CK_INFO.libraryVersion offset");
static_assert(sizeof(CK_INFO) == (sizeof(CK_ULONG) == 8 ? 88 : 76), "CK_INFO size");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_Initialize) == sizeof(void *),
              "CK_FUNCTION_LIST: C_Initialize must sit at pointer alignment");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_Finalize) == 2 * sizeof(void *),
              "CK_FUNCTION_LIST: C_Finalize offset");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_GetInfo) == 3 * sizeof(void *),
              "CK_FUNCTION_LIST: C_GetInfo offset");

#endif // PKCS11_MINIMAL_H
