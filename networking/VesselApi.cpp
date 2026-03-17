#include "VesselApi.h"
#include "ApiEndpoints.h"
#include <QJsonArray>
#include <QJsonObject>
#include <QDebug>

VesselApi::VesselApi(HttpClient* client, QObject* parent)
    : BaseApi(client, parent) {}

void VesselApi::fetchAll(std::function<void(const QList<Vessel>&)> successCb,
                         ErrorCb errorCb)
{
    if (!ensureClient(errorCb)) return;

    const QString createUrl = ApiEndpoints::SimulationCreate();
    qDebug().noquote() << "[VesselApi] POST" << createUrl;

    // Step 1: create (or resume) a simulation to get a simulationId
    client()->post(createUrl, {}, [
        this,
        successCb = std::move(successCb),
        errorCb
    ](QRestReply& reply) mutable {
        qDebug().noquote() << "[VesselApi] ←" << reply.httpStatus() << "POST /simulation";

        expectObject(reply, errorCb, [&](const QJsonObject& obj) {
            const QString simulationId = obj["simulationId"].toString();
            if (simulationId.isEmpty()) {
                ErrorResult err{ reply.httpStatus(), "simulationId missing in response", nullptr };
                if (errorCb) errorCb(err);
                return;
            }

            qDebug().noquote() << "[VesselApi] simulationId =" << simulationId;

            // Step 2: fetch the vessels for this simulation
            const QString vesselsUrl = ApiEndpoints::SimulationVessels(simulationId);
            qDebug().noquote() << "[VesselApi] GET" << vesselsUrl;

            client()->get(vesselsUrl, [
                successCb = std::move(successCb),
                errorCb,
                simulationId
            ](QRestReply& reply) mutable {
                qDebug().noquote() << "[VesselApi] ←" << reply.httpStatus()
                                   << "GET /simulation/" + simulationId + "/vessels";

                // Response is a JSON array: [{ "AIS": { ... } }, ...]
                expectArray(reply, errorCb, [&](const QJsonArray& arr) {
                    if (!successCb) return;

                    QList<Vessel> vessels;
                    vessels.reserve(arr.size());

                    for (const QJsonValue& val : arr) {
                        const QJsonObject ais = val.toObject()["AIS"].toObject();
                        if (ais.isEmpty()) continue;

                        Vessel vessel;
                        vessel.fromAIS(ais);
                        vessels.append(vessel);
                    }

                    qDebug().noquote() << "[VesselApi] ← parsed" << vessels.size() << "vessels";
                    successCb(vessels);
                });
            });
        });
    });
}
