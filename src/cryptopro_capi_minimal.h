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
// Экспорт ОТКРЫТОГО ключа контейнера: публичные данные, нужны только для
// сопоставления контейнера с сертификатом по открытому ключу.
typedef Bool (*CryptExportKeyFn)(CryptKey, CryptKey, Dword, Dword, Byte *, Dword *);
// Запись (v1.3): создание контейнера и генерация ключевой пары внутри него.
// Используются ТОЛЬКО в отдельном helper-режиме записи.
// CapiLite повторяет и системную часть Win32: код последней ошибки провайдера
// доступен через GetLastError. Без него любое сообщение о неудаче — догадка,
// поэтому символ резолвится как необязательный и код показывается как есть.
typedef Dword (*GetLastErrorFn)();
typedef Bool (*CryptGenKeyFn)(CryptProv, Dword, Dword, CryptKey *);
typedef Bool (*CryptSetProvParamFn)(CryptProv, Dword, const Byte *, Dword);

// PKCS#10 (v1.3): запрос кодирует и подписывает сам провайдер. Так не нужно
// разбирать раскладку PUBLICKEYBLOB ГОСТ и угадывать порядок байт подписи.
struct DataBlob
{
    Dword size;
    Byte *data;
};

struct BitBlob
{
    Dword size;
    Byte *data;
    Dword unusedBits;
};

struct AlgorithmIdentifier
{
    char *objectId;
    DataBlob parameters;
};

struct PublicKeyInfo
{
    AlgorithmIdentifier algorithm;
    BitBlob publicKey;
};

struct CertRequestInfo
{
    Dword version;
    DataBlob subject;
    PublicKeyInfo subjectPublicKeyInfo;
    Dword attributeCount;
    void *attributes;
};

typedef Bool (*CertStrToNameAFn)(
        Dword, const char *, Dword, void *, Byte *, Dword *, const char **);
typedef Bool (*CryptExportPublicKeyInfoFn)(
        CryptProv, Dword, Dword, PublicKeyInfo *, Dword *);
typedef Bool (*CryptSignAndEncodeCertificateFn)(
        CryptProv, Dword, Dword, const char *, const void *,
        const AlgorithmIdentifier *, const void *, Byte *, Dword *);
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
// Перечисление считывателей: режим контейнера задаётся выбором считывателя, а не
// параметром, поэтому список нужен, чтобы предлагать реально существующие, а не
// выдуманные имена. Значение из официального WinCryptEx.h КриптоПро (сверено по
// двум копиям заголовка); см. docs/RESEARCH.md.
static const Dword PpEnumReaders = 114;
// Тот же параметр с этим флагом отдаёт ИМЯ НОСИТЕЛЯ, а не считывателя: в
// интерфейсе КриптоПро это отдельный список «Режим работы»
// (`rutoken_ecp_…` — CSP, `pkcs`+`11_rutoken_ecp_…` — активный токен,
// `rutoken_fkc_…` — ФКН). Значение из WinCryptEx.h.
static const Dword CryptMedia = 0x00000020U;

// Спецификации ключа контейнера и параметр чтения привязанного сертификата.
static const Dword AtKeyExchange = 1;
static const Dword AtSignature = 2;
static const Dword KpCertificate = 26;
static const Dword PublicKeyBlob = 6;
// Флаги CryptAcquireContext для записи: создание нового контейнера и удаление
// контейнера (последнее допустимо только как откат собственного создания).
static const Dword CryptNewKeyset = 0x00000008U;
static const Dword CryptDeleteKeyset = 0x00000010U;
// PIN-код контейнера передаём сами, чтобы CSP не поднимал системный диалог.
static const Dword PpKeyExchangePin = 32;
static const Dword PpSignaturePin = 33;
// Версия провайдера (старший/младший байт) — для строки версии КриптоПро CSP.
static const Dword PpVersion = 5;

// Кодирование запроса на сертификат.
static const Dword X509AsnEncoding = 0x00000001U;
static const Dword CertX500NameStr = 3;
// Тип кодируемой структуры передаётся как псевдоуказатель (LPCSTR small id).
static const char *const CertRequestToBeSigned = reinterpret_cast<const char *>(4);
// OID алгоритмов подписи ГОСТ Р 34.10-2012.
static const char *const OidGost2012_256Signature = "1.2.643.7.1.1.3.2";
static const char *const OidGost2012_512Signature = "1.2.643.7.1.1.3.3";

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
static_assert(offsetof(DataBlob, data) == sizeof(void *), "CRYPT_DATA_BLOB layout");
static_assert(offsetof(BitBlob, data) == sizeof(void *), "CRYPT_BIT_BLOB layout");
static_assert(offsetof(BitBlob, unusedBits) == 2 * sizeof(void *),
              "CRYPT_BIT_BLOB unused bits offset");
static_assert(offsetof(AlgorithmIdentifier, parameters) == sizeof(void *),
              "CRYPT_ALGORITHM_IDENTIFIER layout");
static_assert(offsetof(PublicKeyInfo, publicKey) == 3 * sizeof(void *),
              "CERT_PUBLIC_KEY_INFO layout");
static_assert(offsetof(CertRequestInfo, subject) == sizeof(void *),
              "CERT_REQUEST_INFO subject offset");
static_assert(offsetof(CertRequestInfo, subjectPublicKeyInfo) == 3 * sizeof(void *),
              "CERT_REQUEST_INFO public key offset");

} // namespace capi

#endif // CRYPTOPRO_CAPI_MINIMAL_H
