#ifndef CRYPTOPRO_CAPI_MINIMAL_H
#define CRYPTOPRO_CAPI_MINIMAL_H

#include <QtCore/QtGlobal>
#include <cstddef>

// Минимальный ABI CryptoAPI/CapiLite, необходимый read-only адаптеру v1.2.
// Proprietary заголовки и библиотеки КриптоПро не нужны при сборке: функции
// разрешаются из внешней libcapi20.so только во время выполнения.
namespace capi {

typedef quint32 Dword;
typedef qint32 Bool;
typedef unsigned char Byte;
typedef quintptr CryptProv;
typedef quintptr CryptKey;
typedef void *CertStore;
// CapiLite следует платформенному wchar_t: на Linux/Aurora это UTF-32,
// в отличие от 16-битного WCHAR Windows.
typedef wchar_t WideChar;

struct CertContext
{
    Dword encodingType;
    Byte *encoded;
    Dword encodedSize;
    void *certInfo;
    CertStore certStore;
};

struct CryptKeyProvInfo
{
    WideChar *containerName;
    WideChar *providerName;
    Dword providerType;
    Dword flags;
    Dword providerParameterCount;
    void *providerParameters;
    Dword keySpec;
};

typedef Bool (*CryptEnumProvidersAFn)(
        Dword, Dword *, Dword, Dword *, char *, Dword *);
typedef Bool (*CryptAcquireContextAFn)(
        CryptProv *, const char *, const char *, Dword, Dword);
typedef Bool (*CryptReleaseContextFn)(CryptProv, Dword);
typedef Bool (*CryptGetProvParamFn)(
        CryptProv, Dword, Byte *, Dword *, Dword);
// Чтение сертификата, лежащего ВНУТРИ контейнера. Перечисление хранилища «MY»
// возвращает только установленные (зарегистрированные) сертификаты, поэтому
// носитель, на котором сертификат просто лежит в контейнере, через хранилище не
// виден. Штатный путь CryptoAPI: получить ключ контейнера и прочитать
// привязанный к нему сертификат параметром KP_CERTIFICATE.
typedef Bool (*CryptGetUserKeyFn)(CryptProv, Dword, CryptKey *);
typedef Bool (*CryptGetKeyParamFn)(CryptKey, Dword, Byte *, Dword *, Dword);
typedef Bool (*CryptDestroyKeyFn)(CryptKey);
typedef CertStore (*CertOpenSystemStoreAFn)(CryptProv, const char *);
typedef const CertContext *(*CertEnumCertificatesInStoreFn)(
        CertStore, const CertContext *);
typedef Bool (*CertGetCertificateContextPropertyFn)(
        const CertContext *, Dword, void *, Dword *);
typedef Bool (*CertFreeCertificateContextFn)(const CertContext *);
typedef Bool (*CryptAcquireCertificatePrivateKeyFn)(
        const CertContext *, Dword, void *, CryptProv *, Dword *, Bool *);
typedef Bool (*CertCloseStoreFn)(CertStore, Dword);

static const Dword ProvGost2001Dh = 75;
static const Dword ProvGost2012_256 = 80;
static const Dword ProvGost2012_512 = 81;

static const Dword CryptVerifyContext = 0xf0000000U;
static const Dword CryptSilent = 0x00000040U;
static const Dword CryptFirst = 0x00000001U;
static const Dword CryptUnique = 0x00000008U;
static const Dword CryptFqcn = 0x00000010U;
static const Dword PpEnumContainers = 2;

// Спецификации ключа контейнера и параметр чтения привязанного сертификата.
static const Dword AtKeyExchange = 1;
static const Dword AtSignature = 2;
static const Dword KpCertificate = 26;

static const Dword CertKeyProvInfoPropId = 2;
static const Dword CryptAcquireCompareKeyFlag = 0x00000004U;
static const Dword CryptAcquireSilentFlag = 0x00000040U;

static_assert(sizeof(Dword) == 4, "CAPI DWORD must be 32-bit");
static_assert(sizeof(CryptProv) == sizeof(void *), "CAPI handle must be pointer-sized");
static_assert(offsetof(CertContext, encoded) == sizeof(void *),
              "CERT_CONTEXT pointer alignment");
static_assert(offsetof(CertContext, encodedSize) == 2 * sizeof(void *),
              "CERT_CONTEXT encoded size offset");
static_assert(offsetof(CryptKeyProvInfo, providerType) == 2 * sizeof(void *),
              "CRYPT_KEY_PROV_INFO provider type offset");

} // namespace capi

#endif // CRYPTOPRO_CAPI_MINIMAL_H
