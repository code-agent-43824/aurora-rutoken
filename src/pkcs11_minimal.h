// Minimal PKCS#11 v2.40 ABI declarations needed by diagnostics.cpp.
//
// The declarations are based on the functionally equivalent public-domain
// headers maintained by Latchset:
// https://github.com/latchset/pkcs11-headers/tree/main/public-domain/2.40
// Only the C_GetFunctionList -> C_Initialize/C_Finalize/C_GetInfo prefix is
// retained here. PKCS#11 structures use the required one-byte alignment.

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

#pragma pack(push, 1)

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

#pragma pack(pop)

static_assert(sizeof(CK_VERSION) == 2, "PKCS#11 CK_VERSION ABI mismatch");
static_assert(offsetof(CK_INFO, manufacturerID) == 2, "PKCS#11 CK_INFO packing mismatch");
static_assert(offsetof(CK_FUNCTION_LIST_PREFIX, C_Initialize) == 2,
              "PKCS#11 function-list packing mismatch");

#endif // PKCS11_MINIMAL_H
