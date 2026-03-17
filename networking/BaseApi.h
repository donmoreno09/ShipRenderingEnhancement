#ifndef BASEAPI_H
#define BASEAPI_H

#include <QObject>
#include <QByteArray>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRestReply>

#include "ApiTypes.h"
#include "HttpClient.h"

class BaseApi : public QObject
{
    Q_OBJECT

public:
    explicit BaseApi(HttpClient* client, QObject* parent = nullptr)
        : QObject(parent), m_client(client) {}

protected:
    HttpClient* client() const { return m_client; }

    bool ensureClient(ErrorCb& errorCb) const
    {
        if (m_client) return true;
        emitError(errorCb, ErrorResult{0, "HttpClient is null", nullptr});
        return false;
    }

    static void emitError(ErrorCb& errorCb, const ErrorResult& err)
    {
        if (errorCb) errorCb(err);
    }

    static ErrorResult fromReply(QRestReply& reply, const QString& messageOverride = "")
    {
        auto* nr = reply.networkReply();
        const int status = reply.httpStatus();

        QString reason;
        if (nr) {
            reason = nr->attribute(QNetworkRequest::HttpReasonPhraseAttribute).toString();
        }

        QString msg = messageOverride;
        if (msg.isEmpty()) {
            if (!reason.isEmpty()) msg = QString("HTTP %1: %2").arg(status).arg(reason);
            else msg = QString("HTTP %1").arg(status);
        }

        return ErrorResult{ status, msg, nr };
    }

    template <typename Fn>
    requires std::invocable<Fn, const QJsonDocument&>
    static void withJson(QRestReply& reply, ErrorCb& errorCb, Fn&& fn)
    {
        if (!reply.isSuccess()) {
            emitError(errorCb, fromReply(reply));
            return;
        }

        auto doc = reply.readJson();
        if (!doc) {
            emitError(errorCb, fromReply(reply, "Invalid JSON response"));
            return;
        }

        fn(*doc);
    }

    template<typename Fn>
    requires std::invocable<Fn, const QJsonArray&>
    static void expectArray(QRestReply& reply, ErrorCb& errorCb, Fn&& fn)
    {
        withJson(reply, errorCb, [&](const QJsonDocument& doc) {
            if (!doc.isArray()) {
                emitError(errorCb, fromReply(reply, "Unexpected JSON type"));
                return;
            }
            fn(doc.array());
        });
    }

    template<typename Fn>
    requires std::invocable<Fn, const QJsonObject&>
    static void expectObject(QRestReply& reply, ErrorCb& errorCb, Fn&& fn)
    {
        withJson(reply, errorCb, [&](const QJsonDocument& doc) {
            if (!doc.isObject()) {
                emitError(errorCb, fromReply(reply, "Unexpected JSON type"));
                return;
            }
            fn(doc.object());
        });
    }

    template<typename Fn>
    requires std::invocable<Fn, const QString&>
    static void expectString(QRestReply& reply, ErrorCb& errorCb, Fn&& fn)
    {
        if (!reply.isSuccess()) {
            emitError(errorCb, fromReply(reply));
            return;
        }

        QString uuid = QString::fromUtf8(reply.readBody()).remove('\"');
        fn(uuid);
    }

    template<typename Fn>
    requires std::invocable<Fn, const QByteArray&>
    static void expectRaw(QRestReply& reply, ErrorCb& errorCb, Fn&& fn)
    {
        if (!reply.isSuccess()) {
            emitError(errorCb, fromReply(reply));
            return;
        }
        fn(reply.readBody());
    }

private:
    HttpClient* m_client = nullptr;
};

#endif // BASEAPI_H
