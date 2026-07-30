#include "cryptoprosession.h"
#include "cryptopro_capi_minimal.h"

#include <QtConcurrent/QtConcurrent>
#include <QtCore/QCryptographicHash>
#include <QtCore/QDateTime>
#include <QtCore/QHash>
#include <QtCore/QSet>
#include <QtCore/QStringList>
#include <QtCore/QTextCodec>
#include <QtNetwork/QSslCertificate>

namespace {

struct Api
{
    capi::CryptEnumProvidersAFn enumProviders = nullptr;
    capi::CryptAcquireContextAFn acquireContext = nullptr;
    capi::CryptReleaseContextFn releaseContext = nullptr;
    capi::CryptGetProvParamFn getProvParam = nullptr;
    capi::CertOpenSystemStoreAFn openSystemStore = nullptr;
    capi::CertEnumCertificatesInStoreFn enumCertificates = nullptr;
    capi::CertGetCertificateContextPropertyFn getCertificateProperty = nullptr;
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
    capi::Dword capacity = 0;
    if (!api.getProvParam(provider, capi::PpEnumContainers, nullptr, &capacity, flags)
            || capacity == 0)
        return out;
    QByteArray buffer(static_cast<int>(capacity), '\0');
    for (;;) {
        buffer.fill('\0');
        capi::Dword actual = capacity;
        if (!api.getProvParam(provider, capi::PpEnumContainers,
                              reinterpret_cast<capi::Byte *>(buffer.data()), &actual, flags))
            break;

        const QString first = fromCapiText(buffer.constData(), buffer.size());
        const int secondOffset = buffer.indexOf('\0') + 1;
        const QString second = secondOffset > 0 && secondOffset < buffer.size()
                ? fromCapiText(buffer.constData() + secondOffset,
                               buffer.size() - secondOffset)
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

QString bindingKey(const QString &provider, capi::Dword type, const QString &container)
{
    return provider.trimmed().toLower() + QLatin1Char('|') + QString::number(type)
            + QLatin1Char('|') + normalizedContainerName(container);
}

QVariantMap scan(const Api &api, const QString &libraryPath)
{
    QVariantMap result;
    QVariantList providerRows;
    QVector<Container> rutokenContainers;

    for (capi::Dword index = 0; ; ++index) {
        capi::Dword type = 0;
        capi::Dword size = 0;
        if (!api.enumProviders(index, nullptr, 0, &type, nullptr, &size))
            break;
        if (!isGostProvider(type) || size == 0)
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
    for (const Container &container : rutokenContainers) {
        QVariantMap row;
        row.insert(QStringLiteral("name"), container.displayName);
        row.insert(QStringLiteral("uniqueName"), container.uniqueName);
        row.insert(QStringLiteral("friendlyName"), container.friendlyName);
        row.insert(QStringLiteral("provider"), container.provider);
        row.insert(QStringLiteral("providerType"), container.providerType);
        row.insert(QStringLiteral("algorithm"), providerAlgorithm(container.providerType));
        row.insert(QStringLiteral("certificateCount"), 0);
        containerRows.append(row);
    }

    QVariantList certificates;
    capi::CertStore store = api.openSystemStore(0, "MY");
    if (store) {
        const capi::CertContext *context = nullptr;
        while ((context = api.enumCertificates(store, context)) != nullptr) {
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
            row.insert(QStringLiteral("_containerIndex"), containerIndex);
            row.insert(QStringLiteral("_bindingKey"), bindingKey(
                           container.provider, container.providerType,
                           container.uniqueName.isEmpty()
                           ? container.displayName : container.uniqueName));
            certificates.append(row);
        }
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

    result.insert(QStringLiteral("libraryPath"), libraryPath);
    result.insert(QStringLiteral("providers"), providerRows);
    result.insert(QStringLiteral("containers"), containerRows);
    result.insert(QStringLiteral("certificates"), certificates);
    result.insert(QStringLiteral("status"), rutokenContainers.isEmpty()
                  ? QStringLiteral("КриптоПро CSP найден, контейнеры Рутокена не найдены")
                  : QStringLiteral("Контейнеров Рутокена: %1, сертификатов: %2")
                    .arg(rutokenContainers.size()).arg(certificates.size()));
    return result;
}

} // namespace

CryptoProSession::CryptoProSession(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFutureWatcher<QVariantMap>::finished,
            this, &CryptoProSession::finishRefresh);
}

CryptoProSession::~CryptoProSession()
{
    if (m_watcher.isRunning())
        m_watcher.waitForFinished();
    if (m_library.isLoaded())
        m_library.unload();
}

bool CryptoProSession::loadLibrary()
{
    if (m_library.isLoaded() && m_functions.size() == 9)
        return true;

    const QStringList candidates = {
        QStringLiteral("/usr/lib/3rdparty/ru.cryptopro.csp/lib/libcapi20.so"),
        QStringLiteral("/opt/cprocsp/lib/arm/libcapi20.so"),
        QStringLiteral("/opt/cprocsp/lib/arm64/libcapi20.so"),
        QStringLiteral("/opt/cprocsp/lib/aarch64/libcapi20.so"),
        QStringLiteral("/opt/cprocsp/lib/amd64/libcapi20.so"),
        QStringLiteral("libcapi20.so")
    };
    QStringList errors;
    for (const QString &candidate : candidates) {
        m_library.setFileName(candidate);
        if (!m_library.load()) {
            errors << m_library.errorString();
            continue;
        }
        const char *symbols[] = {
            "CryptEnumProvidersA",
            "CryptAcquireContextA",
            "CryptReleaseContext",
            "CryptGetProvParam",
            "CertOpenSystemStoreA",
            "CertEnumCertificatesInStore",
            "CertGetCertificateContextProperty",
            "CryptAcquireCertificatePrivateKey",
            "CertCloseStore"
        };
        m_functions.clear();
        bool complete = true;
        for (const char *symbol : symbols) {
            const QFunctionPointer function = m_library.resolve(symbol);
            if (!function) {
                complete = false;
                break;
            }
            m_functions.append(function);
        }
        if (complete) {
            m_libraryPath = candidate;
            return true;
        }
        errors << QStringLiteral("%1: отсутствуют функции CapiLite").arg(candidate);
        m_functions.clear();
        m_library.unload();
    }
    m_status = QStringLiteral("КриптоПро CSP не установлен");
    if (!errors.isEmpty())
        m_status += QStringLiteral(" (libcapi20.so не найдена)");
    return false;
}

void CryptoProSession::refresh()
{
    if (m_busy)
        return;
    m_busy = true;
    m_status = QStringLiteral("Чтение КриптоПро CSP…");
    emit changed();

    if (!loadLibrary()) {
        m_available = false;
        m_busy = false;
        m_providers.clear();
        m_containers.clear();
        m_certificates.clear();
        emit changed();
        return;
    }

    m_available = true;
    Api api;
    api.enumProviders = reinterpret_cast<capi::CryptEnumProvidersAFn>(m_functions.at(0));
    api.acquireContext = reinterpret_cast<capi::CryptAcquireContextAFn>(m_functions.at(1));
    api.releaseContext = reinterpret_cast<capi::CryptReleaseContextFn>(m_functions.at(2));
    api.getProvParam = reinterpret_cast<capi::CryptGetProvParamFn>(m_functions.at(3));
    api.openSystemStore = reinterpret_cast<capi::CertOpenSystemStoreAFn>(m_functions.at(4));
    api.enumCertificates =
            reinterpret_cast<capi::CertEnumCertificatesInStoreFn>(m_functions.at(5));
    api.getCertificateProperty =
            reinterpret_cast<capi::CertGetCertificateContextPropertyFn>(m_functions.at(6));
    api.acquireCertificateKey =
            reinterpret_cast<capi::CryptAcquireCertificatePrivateKeyFn>(m_functions.at(7));
    api.closeStore = reinterpret_cast<capi::CertCloseStoreFn>(m_functions.at(8));
    const QString path = m_libraryPath;
    m_watcher.setFuture(QtConcurrent::run([api, path]() { return scan(api, path); }));
}

void CryptoProSession::finishRefresh()
{
    const QVariantMap result = m_watcher.result();
    m_libraryPath = result.value(QStringLiteral("libraryPath")).toString();
    m_providers = result.value(QStringLiteral("providers")).toList();
    m_containers = result.value(QStringLiteral("containers")).toList();
    m_certificates = result.value(QStringLiteral("certificates")).toList();
    m_status = result.value(QStringLiteral("status")).toString();
    m_busy = false;
    emit changed();
}
