#include "HttpClient.h"

#include <QHttpHeaders>
#include <QtGlobal>
#include <cmath>

HttpClient::HttpClient(QObject *parent)
    : QObject(parent)
    , m_rest(&m_nam, this)
    , m_factory(QUrl())
{
    // Common headers
    QHttpHeaders headers;
    headers.append(QHttpHeaders::WellKnownHeader::Accept, "application/json");
    headers.append(QHttpHeaders::WellKnownHeader::ContentType, "application/json");
    headers.append("ngrok-skip-browser-warning", "true");
    m_factory.setCommonHeaders(headers);

    // Timeout
    m_factory.setTransferTimeout(std::chrono::seconds(15));
}

HttpClient::HttpClient(const QUrl& baseUrl, QObject *parent)
    : QObject(parent)
    , m_rest(&m_nam, this)
    , m_factory(baseUrl)
{
    // Common headers
    QHttpHeaders headers;
    headers.append(QHttpHeaders::WellKnownHeader::Accept, "application/json");
    headers.append(QHttpHeaders::WellKnownHeader::ContentType, "application/json");
    m_factory.setCommonHeaders(headers);

    // Timeout
    m_factory.setTransferTimeout(std::chrono::seconds(15));
}

void HttpClient::setBaseUrl(const QUrl& baseUrl)
{
    m_factory.setBaseUrl(baseUrl);
}

void HttpClient::setBearerToken(const QByteArray& token)
{
    m_factory.setBearerToken(token);
}

void HttpClient::clearBearerToken()
{
    m_factory.setBearerToken(QByteArray{});
}

QNetworkRequest HttpClient::buildRequest(const QString& urlOrPath) const
{
    const QUrl url(urlOrPath);

    // 1) Relative path -> use factory join (baseUrl + path)
    if (url.isValid() && url.isRelative()) {
        return m_factory.createRequest(urlOrPath);
    }

    // 2) Absolute URL -> create a "configured" request, then override URL
    //    (keeps common headers, bearer, timeout, etc.)
    QNetworkRequest req = m_factory.createRequest();
    if (url.isValid())
        req.setUrl(url);
    else
        req.setUrl(QUrl{}); // invalid; caller handles
    return req;
}

int HttpClient::retryDelayMs(const RetryPolicy& policy, int attemptNo)
{
    const int expIndex = qMax(0, attemptNo - 1);
    const double raw = policy.baseDelayMs * std::pow(policy.multiplier, expIndex); // baseDelayMs * (multiplier) ^ exponent
    const int ms = static_cast<int>(raw);
    return qBound(0, ms, policy.maxDelayMs);
}

void HttpClient::autoDeleteHandle(RequestHandle *handle)
{
    QObject::connect(handle, &RequestHandle::finished, handle, &QObject::deleteLater);
    QObject::connect(handle, &RequestHandle::failed,   handle, &QObject::deleteLater);
}

bool HttpClient::shouldRetry(const QRestReply& reply, const RetryPolicy& policy, int attemptNo) const
{
    if (attemptNo >= policy.maxAttempts)
        return false;

    if (policy.shouldRetry)
        return policy.shouldRetry(reply);

    const int status = reply.httpStatus();

    // Network/transport error (no valid HTTP status)
    if (status <= 0)
        return policy.retryOnNetworkError;

    return policy.retryHttpStatus.contains(status);
}
