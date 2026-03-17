#include "VesselApi.h"
#include "ApiEndpoints.h"
#include <QJsonArray>
#include <QDebug>

VesselApi::VesselApi(HttpClient* client, QObject* parent)
    : BaseApi(client, parent) {}

void VesselApi::fetchAll(std::function<void(const QList<Vessel>&)> successCb,
                         ErrorCb errorCb)
{
    if (!ensureClient(errorCb)) return;

    const QString url = ApiEndpoints::Vessels();
    qDebug().noquote() << "[VesselApi] GET" << url;

    client()->get(url, [
        successCb = std::move(successCb),
        errorCb   = std::move(errorCb)
    ](QRestReply& reply) mutable {
        qDebug().noquote() << "[VesselApi] ←" << reply.httpStatus() << "GET /vessels";

        // Server returns { count: N, vessels: [...] }
        expectObject(reply, errorCb, [&](const QJsonObject& obj) {
            if (!successCb) return;

            const QJsonArray arr = obj["vessels"].toArray();
            QList<Vessel> vessels;
            vessels.reserve(arr.size());

            for (const QJsonValue& val : arr) {
                Vessel vessel;
                vessel.fromJson(val.toObject());
                vessels.append(vessel);
            }

            qDebug().noquote() << "[VesselApi] ← parsed" << vessels.size() << "vessels";
            successCb(vessels);
        });
    });
}
