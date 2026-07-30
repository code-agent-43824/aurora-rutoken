#include "cryptoprosession.h"
#include "cryptopro_capi_minimal.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QCryptographicHash>
#include <QtCore/QDateTime>
#include <QtCore/QHash>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonParseError>
#include <QtCore/QLibrary>
#include <QtCore/QSet>
#include <QtCore/QStringList>
#include <QtCore/QTextCodec>
#include <QtCore/QVector>
#include <QtNetwork/QSslCertificate>
#include <cstdio>

namespace {

const int MaxProviders = 128;
const int MaxContainersPerProvider = 512;
const int MaxCertificates = 4096;
const capi::Dword MaxCapiTextBytes = 64U * 1024U;
const int MaxHelperOutputBytes = 4 * 1024 * 1024;
const int HelperTimeoutMs = 30000;
const char HelperMarker[] = "RUTOKEN_CRYPTOPRO_JSON:";

struct Api
{
    capi::CryptEnumProvidersAFn enumProviders = nullptr;
    capi::CryptAcquireContextAFn acquireContext = nullptr;
    capi::CryptReleaseContextFn releaseContext = nullptr;
    capi::CryptGetProvParamFn getProvParam = nullptr;
    capi::CertOpenSystemStoreAFn openSystemStore = nullptr;
    capi::CertEnumCertificatesInStoreFn enumCertificates = nullptr;
    capi::CertGetCertificateContextPropertyFn getCertificateProperty = nullptr;
    capi::CertFreeCertificateContextFn freeCertificate = nullptr;
    capi::CryptAcquireCertificatePrivateKeyFn acquireCertificateKey = nullptr;
    capi::CertCloseStoreFn closeStore = nullptr;
};

struct Container
{
    QString provider;
    capi::Dword providerType = 0;
    QString uniqueName;
    QString friendlyName;
    QString displayName;
};

QString providerAlgorithm(capi::Dword type)
{
    switch (type) {
    case capi::ProvGost2001Dh:
        return QStringLiteral("ГОСТ Р 34.10-2001");
    case capi::ProvGost2012_256:
        return QStringLiteral("ГОСТ Р 34.10-2012 (256)");
    case capi::ProvGost2012_512:
        return QStringLiteral("ГОСТ Р 34.10-2012 (512)");
    default:
        return QStringLiteral("тип провайдера %1").arg(type);
    }
}

bool isGostProvider(capi::Dword type)
{
    return type == capi::ProvGost2001Dh
            || type == capi::ProvGost2012_256
            || type == capi::ProvGost2012_512;
}

QString fromCapiText(const char *data, int size)
{
    if (!data || size <= 0)
        return QString();
    int length = 0;
    while (length < size && data[length] != '\0')
        ++length;
    // По документации CapiLite CP_ACP на *nix — CP1251.
    QTextCodec *codec = QTextCodec::codecForName("Windows-1251");
    return codec ? codec->toUnicode(data, length) : QString::fromLocal8Bit(data, length);
}

QByteArray toCapiText(const QString &text)
{
    QTextCodec *codec = QTextCodec::codecForName("Windows-1251");
    return codec ? codec->fromUnicode(text) : text.toLocal8Bit();
}

QString boundedUtf16(const capi::WideChar *text, const QByteArray &owner)
{
    if (!text || owner.isEmpty())
        return QString();
    const quintptr begin = reinterpret_cast<quintptr>(owner.constData());
    const quintptr end = begin + static_cast<quintptr>(owner.size());
    const quintptr address = reinterpret_cast<quintptr>(text);
    if (address < begin || address + sizeof(capi::WideChar) > end)
        return QString();
    const int maximum = static_cast<int>((end - address) / sizeof(capi::WideChar));
    int length = 0;
    while (length < maximum && text[length] != 0)
        ++length;
    if (length == maximum)
        return QString();
    if (sizeof(capi::WideChar) == sizeof(ushort))
        return QString::fromUtf16(reinterpret_cast<const ushort *>(text), length);
    return QString::fromUcs4(reinterpret_cast<const uint *>(text), length);
}

QString normalizedContainerName(QString value)
{
    value = value.trimmed().toLower();
    value.replace(QLatin1Char('/'), QLatin1Char('\\'));
    while (value.endsWith(QLatin1Char('\\')))
        value.chop(1);
    return value;
}

QString containerLeaf(const QString &value)
{
    const QString normalized = normalizedContainerName(value);
    return normalized.mid(normalized.lastIndexOf(QLatin1Char('\\')) + 1);
}

bool sameContainerName(const QString &left, const QString &right)
{
    const QString a = normalizedContainerName(left);
    const QString b = normalizedContainerName(right);
    if (a.isEmpty() || b.isEmpty())
        return false;
    return a == b || containerLeaf(a) == containerLeaf(b);
}

bool isRutokenContainer(const Container &container)
{
    const QString haystack = (container.uniqueName + QLatin1Char(' ')
                              + container.friendlyName).toLower();
    return haystack.contains(QStringLiteral("rutoken"))
            || haystack.contains(QStringLiteral("актив"))
            || haystack.contains(QStringLiteral("aktiv"));
}

QVector<Container> enumerateContainers(const Api &api, capi::CryptProv provider,
                                       const QString &providerName, capi::Dword providerType)
{
    QVector<Container> out;
    capi::Dword flags = capi::CryptFirst | capi::CryptUnique | capi::CryptFqcn;
    QByteArray buffer(static_cast<int>(MaxCapiTextBytes), '\0');
    for (int item = 0; item < MaxContainersPerProvider; ++item) {
        buffer.fill('\0');
        capi::Dword actual = static_cast<capi::Dword>(buffer.size());
        if (!api.getProvParam(provider, capi::PpEnumContainers,
                              reinterpret_cast<capi::Byte *>(buffer.data()), &actual, flags))
            break;
        if (actual == 0 || actual > static_cast<capi::Dword>(buffer.size()))
            break;

        const int validBytes = static_cast<int>(actual);
        const QString first = fromCapiText(buffer.constData(), validBytes);
        int firstTerminator = buffer.indexOf('\0', 0);
        if (firstTerminator >= validBytes)
            firstTerminator = -1;
        const int secondOffset = firstTerminator < 0 ? validBytes : firstTerminator + 1;
        const QString second = secondOffset < validBytes
                ? fromCapiText(buffer.constData() + secondOffset,
                               validBytes - secondOffset)
                : QString();

        Container container;
        container.provider = providerName;
        container.providerType = providerType;
        container.uniqueName = first;
        container.friendlyName = second;
        container.displayName = second.isEmpty() ? first : second;
        if (isRutokenContainer(container))
            out.append(container);
        flags &= ~capi::CryptFirst;
    }
    return out;
}

QString firstInfo(const QStringList &values)
{
    return values.isEmpty() ? QString() : values.first();
}

QString distinguishedName(const QSslCertificate &certificate, bool issuer)
{
    struct Part { QSslCertificate::SubjectInfo field; const char *name; };
    const Part parts[] = {
        { QSslCertificate::CommonName, "CN" },
        { QSslCertificate::Organization, "O" },
        { QSslCertificate::OrganizationalUnitName, "OU" },
        { QSslCertificate::LocalityName, "L" },
        { QSslCertificate::StateOrProvinceName, "ST" },
        { QSslCertificate::CountryName, "C" }
    };
    QStringList out;
    for (const Part &part : parts) {
        const QString value = firstInfo(issuer
                ? certificate.issuerInfo(part.field)
                : certificate.subjectInfo(part.field));
        if (!value.isEmpty())
            out << QString::fromLatin1(part.name) + QLatin1Char('=') + value;
    }
    return out.join(QStringLiteral(", "));
}

bool readTlv(const QByteArray &der, int &position, quint8 expectedTag,
             int &contentStart, int &contentLength, int &next)
{
    if (position < 0 || position + 2 > der.size()
            || static_cast<quint8>(der.at(position)) != expectedTag)
        return false;
    int cursor = position + 1;
    quint32 length = static_cast<quint8>(der.at(cursor++));
    if (length & 0x80U) {
        const int count = static_cast<int>(length & 0x7fU);
        if (count == 0 || count > 4 || cursor + count > der.size())
            return false;
        length = 0;
        for (int i = 0; i < count; ++i)
            length = (length << 8) | static_cast<quint8>(der.at(cursor++));
    }
    if (length > static_cast<quint32>(der.size() - cursor))
        return false;
    contentStart = cursor;
    contentLength = static_cast<int>(length);
    next = cursor + contentLength;
    position = cursor;
    return true;
}

QString decodeOid(const QByteArray &value)
{
    if (value.isEmpty())
        return QString();
    const quint8 first = static_cast<quint8>(value.at(0));
    QStringList parts;
    parts << QString::number(first / 40) << QString::number(first % 40);
    quint64 component = 0;
    for (int i = 1; i < value.size(); ++i) {
        const quint8 byte = static_cast<quint8>(value.at(i));
        component = (component << 7) | (byte & 0x7fU);
        if (!(byte & 0x80U)) {
            parts << QString::number(component);
            component = 0;
        }
    }
    return parts.join(QLatin1Char('.'));
}

QString certificateAlgorithm(const QByteArray &der, capi::Dword providerType)
{
    int position = 0, start = 0, length = 0, next = 0;
    if (!readTlv(der, position, 0x30, start, length, next))
        return providerAlgorithm(providerType);
    position = start;
    if (!readTlv(der, position, 0x30, start, length, next))
        return providerAlgorithm(providerType);
    position = next;
    if (!readTlv(der, position, 0x30, start, length, next))
        return providerAlgorithm(providerType);
    position = start;
    if (!readTlv(der, position, 0x06, start, length, next))
        return providerAlgorithm(providerType);
    const QString oid = decodeOid(der.mid(start, length));
    if (oid == QStringLiteral("1.2.643.7.1.1.3.2"))
        return QStringLiteral("ГОСТ Р 34.10-2012/256");
    if (oid == QStringLiteral("1.2.643.7.1.1.3.3"))
        return QStringLiteral("ГОСТ Р 34.10-2012/512");
    if (oid == QStringLiteral("1.2.643.2.2.3"))
        return QStringLiteral("ГОСТ Р 34.10-2001");
    if (oid == QStringLiteral("1.2.840.113549.1.1.11"))
        return QStringLiteral("RSA/SHA-256");
    return oid.isEmpty() ? providerAlgorithm(providerType) : oid;
}

QString physicalContainerKey(const Container &container)
{
    // При CRYPT_UNIQUE | CRYPT_FQCN второе имя содержит полный физический
    // путь носителя. Оно одинаково у provider aliases 75/80/81, но различает
    // одноимённые контейнеры на разных Рутокенах.
    const QString fqcn = normalizedContainerName(container.friendlyName);
    if (!fqcn.isEmpty())
        return fqcn;
    return normalizedContainerName(container.uniqueName);
}

QVariantMap scan(const Api &api, const QString &libraryPath)
{
    QVariantMap result;
    QVariantList providerRows;
    QVector<Container> rutokenContainers;

    for (capi::Dword index = 0; index < static_cast<capi::Dword>(MaxProviders);
         ++index) {
        capi::Dword type = 0;
        capi::Dword size = 0;
        if (!api.enumProviders(index, nullptr, 0, &type, nullptr, &size))
            break;
        if (!isGostProvider(type) || size == 0 || size > MaxCapiTextBytes)
            continue;
        QByteArray name(static_cast<int>(size), '\0');
        if (!api.enumProviders(index, nullptr, 0, &type, name.data(), &size))
            continue;
        const QString providerName = fromCapiText(name.constData(), name.size());
        const QByteArray providerBytes = toCapiText(providerName);

        capi::CryptProv provider = 0;
        if (!api.acquireContext(&provider, nullptr, providerBytes.constData(), type,
                                capi::CryptVerifyContext | capi::CryptSilent))
            continue;
        const QVector<Container> listed = enumerateContainers(
                    api, provider, providerName, type);
        api.releaseContext(provider, 0);

        QVariantMap providerRow;
        providerRow.insert(QStringLiteral("name"), providerName);
        providerRow.insert(QStringLiteral("type"), type);
        providerRow.insert(QStringLiteral("algorithm"), providerAlgorithm(type));
        providerRow.insert(QStringLiteral("rutokenContainerCount"), listed.size());
        providerRows.append(providerRow);
        rutokenContainers += listed;
    }

    QVariantList containerRows;
    QVector<int> logicalContainerIndices;
    QHash<QString, int> logicalContainerByKey;
    for (int rawIndex = 0; rawIndex < rutokenContainers.size(); ++rawIndex) {
        const Container &container = rutokenContainers.at(rawIndex);
        QString physicalKey = physicalContainerKey(container);
        if (physicalKey.isEmpty())
            physicalKey = QStringLiteral("raw:%1").arg(rawIndex);

        int logicalIndex = logicalContainerByKey.value(physicalKey, -1);
        if (logicalIndex < 0) {
            QVariantMap row;
            row.insert(QStringLiteral("name"), container.displayName);
            row.insert(QStringLiteral("uniqueName"), container.uniqueName);
            row.insert(QStringLiteral("friendlyName"), container.friendlyName);
            row.insert(QStringLiteral("provider"), container.provider);
            row.insert(QStringLiteral("providerType"), container.providerType);
            row.insert(QStringLiteral("providerTypes"),
                       QStringList(QString::number(container.providerType)));
            row.insert(QStringLiteral("providerTypesText"),
                       QString::number(container.providerType));
            row.insert(QStringLiteral("algorithms"),
                       QStringList(providerAlgorithm(container.providerType)));
            row.insert(QStringLiteral("algorithm"),
                       providerAlgorithm(container.providerType));
            row.insert(QStringLiteral("certificateCount"), 0);
            row.insert(QStringLiteral("_physicalKey"), physicalKey);
            logicalIndex = containerRows.size();
            containerRows.append(row);
            logicalContainerByKey.insert(physicalKey, logicalIndex);
        } else {
            QVariantMap row = containerRows.at(logicalIndex).toMap();
            QStringList types = row.value(QStringLiteral("providerTypes")).toStringList();
            const QString type = QString::number(container.providerType);
            if (!types.contains(type))
                types.append(type);
            QStringList algorithms = row.value(QStringLiteral("algorithms")).toStringList();
            const QString algorithm = providerAlgorithm(container.providerType);
            if (!algorithms.contains(algorithm))
                algorithms.append(algorithm);
            row.insert(QStringLiteral("providerTypes"), types);
            row.insert(QStringLiteral("providerTypesText"), types.join(QStringLiteral(", ")));
            row.insert(QStringLiteral("algorithms"), algorithms);
            row.insert(QStringLiteral("algorithm"), algorithms.join(QStringLiteral(" / ")));
            containerRows[logicalIndex] = row;
        }
        logicalContainerIndices.append(logicalIndex);
    }

    QVariantList certificates;
    capi::CertStore store = api.openSystemStore(0, "MY");
    if (store) {
        const capi::CertContext *context = nullptr;
        for (int certificateIndex = 0; certificateIndex < MaxCertificates;
             ++certificateIndex) {
            context = api.enumCertificates(store, context);
            if (!context)
                break;
            if (!context->encoded || context->encodedSize == 0
                    || context->encodedSize > 16U * 1024U * 1024U)
                continue;
            const QByteArray der(reinterpret_cast<const char *>(context->encoded),
                                 static_cast<int>(context->encodedSize));

            capi::Dword propertySize = 0;
            if (!api.getCertificateProperty(context, capi::CertKeyProvInfoPropId,
                                            nullptr, &propertySize)
                    || propertySize < sizeof(capi::CryptKeyProvInfo)
                    || propertySize > 1024U * 1024U)
                continue;
            QByteArray property(static_cast<int>(propertySize), '\0');
            if (!api.getCertificateProperty(context, capi::CertKeyProvInfoPropId,
                                            property.data(), &propertySize))
                continue;
            const capi::CryptKeyProvInfo *info =
                    reinterpret_cast<const capi::CryptKeyProvInfo *>(property.constData());
            const QString boundContainer = boundedUtf16(info->containerName, property);
            const QString boundProvider = boundedUtf16(info->providerName, property);

            int containerIndex = -1;
            for (int i = 0; i < rutokenContainers.size(); ++i) {
                const Container &candidate = rutokenContainers.at(i);
                const bool providerMatches = boundProvider.isEmpty()
                        || candidate.provider.compare(boundProvider, Qt::CaseInsensitive) == 0;
                if (providerMatches && candidate.providerType == info->providerType
                        && (sameContainerName(boundContainer, candidate.uniqueName)
                            || sameContainerName(boundContainer, candidate.friendlyName)
                            || sameContainerName(boundContainer, candidate.displayName))) {
                    containerIndex = i;
                    break;
                }
            }
            if (containerIndex < 0)
                continue;

            const Container &container = rutokenContainers.at(containerIndex);
            const int logicalContainerIndex = logicalContainerIndices.at(containerIndex);
            const QSslCertificate certificate(der, QSsl::Der);
            capi::CryptProv keyProvider = 0;
            capi::Dword keySpec = 0;
            capi::Bool callerFree = 0;
            const bool privateKeyAvailable = api.acquireCertificateKey(
                        context,
                        capi::CryptAcquireSilentFlag | capi::CryptAcquireCompareKeyFlag,
                        nullptr, &keyProvider, &keySpec, &callerFree) != 0;
            if (privateKeyAvailable && callerFree)
                api.releaseContext(keyProvider, 0);

            QVariantMap row;
            const QString sha256 = QString::fromLatin1(
                        QCryptographicHash::hash(der, QCryptographicHash::Sha256).toHex());
            row.insert(QStringLiteral("subject"), certificate.isNull()
                       ? QString() : distinguishedName(certificate, false));
            row.insert(QStringLiteral("issuer"), certificate.isNull()
                       ? QString() : distinguishedName(certificate, true));
            row.insert(QStringLiteral("serial"), certificate.isNull()
                       ? QString() : QString::fromLatin1(certificate.serialNumber()));
            row.insert(QStringLiteral("notBefore"), certificate.effectiveDate().isValid()
                       ? certificate.effectiveDate().toUTC().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss 'UTC'"))
                       : QString());
            row.insert(QStringLiteral("notAfter"), certificate.expiryDate().isValid()
                       ? certificate.expiryDate().toUTC().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss 'UTC'"))
                       : QString());
            row.insert(QStringLiteral("expired"), certificate.expiryDate().isValid()
                       && QDateTime::currentDateTimeUtc() > certificate.expiryDate().toUTC());
            row.insert(QStringLiteral("algorithm"),
                       certificateAlgorithm(der, info->providerType));
            row.insert(QStringLiteral("sha256"), sha256);
            row.insert(QStringLiteral("provider"),
                       boundProvider.isEmpty() ? container.provider : boundProvider);
            row.insert(QStringLiteral("providerType"), info->providerType);
            row.insert(QStringLiteral("container"),
                       boundContainer.isEmpty() ? container.displayName : boundContainer);
            row.insert(QStringLiteral("privateKeyAvailable"), privateKeyAvailable);
            row.insert(QStringLiteral("keySpec"), keySpec);
            row.insert(QStringLiteral("exactDuplicateCount"), 1);
            row.insert(QStringLiteral("containerCertificateCount"), 1);
            row.insert(QStringLiteral("metadataConflict"), false);
            row.insert(QStringLiteral("_containerIndex"), logicalContainerIndex);
            row.insert(QStringLiteral("_bindingKey"),
                       containerRows.at(logicalContainerIndex).toMap()
                       .value(QStringLiteral("_physicalKey")).toString());
            certificates.append(row);
        }
        if (context)
            api.freeCertificate(context);
        api.closeStore(store, 0);
    }

    QHash<QString, int> derCounts;
    QHash<QString, QSet<QString> > derBindings;
    QHash<QString, QSet<QString> > bindingCertificates;
    for (const QVariant &value : certificates) {
        const QVariantMap row = value.toMap();
        const QString sha = row.value(QStringLiteral("sha256")).toString();
        const QString binding = row.value(QStringLiteral("_bindingKey")).toString();
        derCounts[sha] += 1;
        derBindings[sha].insert(binding);
        bindingCertificates[binding].insert(sha);
    }
    for (int i = 0; i < certificates.size(); ++i) {
        QVariantMap row = certificates.at(i).toMap();
        const QString sha = row.value(QStringLiteral("sha256")).toString();
        const QString binding = row.value(QStringLiteral("_bindingKey")).toString();
        row.insert(QStringLiteral("exactDuplicateCount"), derCounts.value(sha));
        row.insert(QStringLiteral("containerCertificateCount"),
                   bindingCertificates.value(binding).size());
        row.insert(QStringLiteral("metadataConflict"), derBindings.value(sha).size() > 1);
        const int containerIndex = row.take(QStringLiteral("_containerIndex")).toInt();
        row.remove(QStringLiteral("_bindingKey"));
        certificates[i] = row;
        if (containerIndex >= 0 && containerIndex < containerRows.size()) {
            QVariantMap container = containerRows.at(containerIndex).toMap();
            container.insert(QStringLiteral("certificateCount"),
                             container.value(QStringLiteral("certificateCount")).toInt() + 1);
            containerRows[containerIndex] = container;
        }
    }
    for (int i = 0; i < containerRows.size(); ++i) {
        QVariantMap row = containerRows.at(i).toMap();
        row.remove(QStringLiteral("_physicalKey"));
        containerRows[i] = row;
    }

    result.insert(QStringLiteral("libraryPath"), libraryPath);
    result.insert(QStringLiteral("providers"), providerRows);
    result.insert(QStringLiteral("containers"), containerRows);
    result.insert(QStringLiteral("certificates"), certificates);
    result.insert(QStringLiteral("status"), containerRows.isEmpty()
                  ? QStringLiteral("КриптоПро CSP найден, контейнеры Рутокена не найдены")
                  : QStringLiteral("Контейнеров Рутокена: %1, сертификатов: %2")
                    .arg(containerRows.size()).arg(certificates.size()));
    return result;
}

QVariantMap executeScan()
{
    const QStringList candidates = {
        QStringLiteral("/usr/lib/3rdparty/ru.cryptopro.csp/lib/libcapi20.so"),
        QStringLiteral("/opt/cprocsp/lib/arm/libcapi20.so"),
        QStringLiteral("/opt/cprocsp/lib/arm64/libcapi20.so"),
        QStringLiteral("/opt/cprocsp/lib/aarch64/libcapi20.so"),
        QStringLiteral("/opt/cprocsp/lib/amd64/libcapi20.so"),
        QStringLiteral("libcapi20.so")
    };
    const char *symbols[] = {
        "CryptEnumProvidersA",
        "CryptAcquireContextA",
        "CryptReleaseContext",
        "CryptGetProvParam",
        "CertOpenSystemStoreA",
        "CertEnumCertificatesInStore",
        "CertGetCertificateContextProperty",
        "CertFreeCertificateContext",
        "CryptAcquireCertificatePrivateKey",
        "CertCloseStore"
    };

    QLibrary library;
    QVector<QFunctionPointer> functions;
    QString libraryPath;
    for (const QString &candidate : candidates) {
        library.setFileName(candidate);
        if (!library.load())
            continue;
        functions.clear();
        bool complete = true;
        for (const char *symbol : symbols) {
            const QFunctionPointer function = library.resolve(symbol);
            if (!function) {
                complete = false;
                break;
            }
            functions.append(function);
        }
        if (complete) {
            libraryPath = candidate;
            break;
        }
        functions.clear();
        library.unload();
    }

    if (functions.size() != 10) {
        QVariantMap result;
        result.insert(QStringLiteral("available"), false);
        result.insert(QStringLiteral("status"),
                      QStringLiteral("КриптоПро CSP не установлен "
                                     "(libcapi20.so не найдена)"));
        result.insert(QStringLiteral("providers"), QVariantList());
        result.insert(QStringLiteral("containers"), QVariantList());
        result.insert(QStringLiteral("certificates"), QVariantList());
        return result;
    }

    Api api;
    api.enumProviders = reinterpret_cast<capi::CryptEnumProvidersAFn>(functions.at(0));
    api.acquireContext = reinterpret_cast<capi::CryptAcquireContextAFn>(functions.at(1));
    api.releaseContext = reinterpret_cast<capi::CryptReleaseContextFn>(functions.at(2));
    api.getProvParam = reinterpret_cast<capi::CryptGetProvParamFn>(functions.at(3));
    api.openSystemStore = reinterpret_cast<capi::CertOpenSystemStoreAFn>(functions.at(4));
    api.enumCertificates =
            reinterpret_cast<capi::CertEnumCertificatesInStoreFn>(functions.at(5));
    api.getCertificateProperty =
            reinterpret_cast<capi::CertGetCertificateContextPropertyFn>(functions.at(6));
    api.freeCertificate =
            reinterpret_cast<capi::CertFreeCertificateContextFn>(functions.at(7));
    api.acquireCertificateKey =
            reinterpret_cast<capi::CryptAcquireCertificatePrivateKeyFn>(functions.at(8));
    api.closeStore = reinterpret_cast<capi::CertCloseStoreFn>(functions.at(9));

    QVariantMap result = scan(api, libraryPath);
    result.insert(QStringLiteral("available"), true);
    return result;
}

} // namespace

CryptoProSession::CryptoProSession(QObject *parent)
    : QObject(parent)
{
    m_helper.setProcessChannelMode(QProcess::SeparateChannels);
    m_helperTimer.setSingleShot(true);
    connect(&m_helper, &QProcess::readyReadStandardOutput,
            this, &CryptoProSession::readHelperOutput);
    connect(&m_helper, &QProcess::readyReadStandardError, this, [this]() {
        m_helper.readAllStandardError();
    });
    connect(&m_helper,
            static_cast<void (QProcess::*)(int, QProcess::ExitStatus)>(&QProcess::finished),
            this, &CryptoProSession::finishHelper);
    connect(&m_helper, &QProcess::errorOccurred,
            this, &CryptoProSession::helperError);
    connect(&m_helperTimer, &QTimer::timeout,
            this, &CryptoProSession::helperTimedOut);
}

CryptoProSession::~CryptoProSession()
{
    m_helperTimer.stop();
    if (m_helper.state() != QProcess::NotRunning) {
        m_helper.kill();
        m_helper.waitForFinished(1000);
    }
}

int CryptoProSession::runScanHelper()
{
    const QByteArray payload = QJsonDocument::fromVariant(executeScan())
            .toJson(QJsonDocument::Compact);
    if (payload.size() > MaxHelperOutputBytes)
        return 2;
    std::fwrite(HelperMarker, 1, sizeof(HelperMarker) - 1, stdout);
    std::fwrite(payload.constData(), 1, static_cast<size_t>(payload.size()), stdout);
    std::fputc('\n', stdout);
    return std::fflush(stdout) == 0 ? 0 : 3;
}

void CryptoProSession::refresh()
{
    if (m_busy)
        return;
    m_busy = true;
    m_status = QStringLiteral("Чтение КриптоПро CSP…");
    m_helperOutput.clear();
    emit changed();

    m_helper.setProgram(QCoreApplication::applicationFilePath());
    m_helper.setArguments(QStringList(QStringLiteral("--cryptopro-scan-helper")));
    m_helper.start(QIODevice::ReadOnly);
    m_helperTimer.start(HelperTimeoutMs);
}

void CryptoProSession::readHelperOutput()
{
    if (!m_busy) {
        m_helper.readAllStandardOutput();
        return;
    }
    m_helperOutput.append(m_helper.readAllStandardOutput());
    if (m_helperOutput.size() > MaxHelperOutputBytes) {
        m_helper.kill();
        failRefresh(QStringLiteral("Ответ КриптоПро CSP слишком большой"));
    }
}

void CryptoProSession::finishHelper(int exitCode, QProcess::ExitStatus exitStatus)
{
    readHelperOutput();
    m_helperTimer.stop();
    if (!m_busy)
        return;
    if (exitStatus != QProcess::NormalExit || exitCode != 0) {
        failRefresh(QStringLiteral("КриптоПро CSP завершил чтение с ошибкой"));
        return;
    }

    const QByteArray marker(HelperMarker, sizeof(HelperMarker) - 1);
    const int markerPosition = m_helperOutput.lastIndexOf(marker);
    if (markerPosition < 0) {
        failRefresh(QStringLiteral("КриптоПро CSP вернул некорректный ответ"));
        return;
    }
    const QByteArray json = m_helperOutput.mid(markerPosition + marker.size()).trimmed();
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(json, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        failRefresh(QStringLiteral("КриптоПро CSP вернул некорректный ответ"));
        return;
    }

    const QVariantMap result = document.toVariant().toMap();
    m_available = result.value(QStringLiteral("available")).toBool();
    m_libraryPath = result.value(QStringLiteral("libraryPath")).toString();
    m_providers = result.value(QStringLiteral("providers")).toList();
    m_containers = result.value(QStringLiteral("containers")).toList();
    m_certificates = result.value(QStringLiteral("certificates")).toList();
    m_status = result.value(QStringLiteral("status")).toString();
    m_busy = false;
    emit changed();
}

void CryptoProSession::helperError(QProcess::ProcessError error)
{
    if (!m_busy || error == QProcess::Crashed)
        return;
    failRefresh(error == QProcess::FailedToStart
                ? QStringLiteral("Не удалось запустить безопасное чтение КриптоПро CSP")
                : QStringLiteral("Ошибка безопасного чтения КриптоПро CSP"));
}

void CryptoProSession::helperTimedOut()
{
    if (!m_busy)
        return;
    m_helper.kill();
    failRefresh(QStringLiteral("КриптоПро CSP не ответил за 30 секунд"));
}

void CryptoProSession::failRefresh(const QString &message)
{
    m_helperTimer.stop();
    if (m_helper.state() != QProcess::NotRunning)
        m_helper.kill();
    m_available = false;
    m_busy = false;
    m_status = message;
    m_libraryPath.clear();
    m_providers.clear();
    m_containers.clear();
    m_certificates.clear();
    emit changed();
}
