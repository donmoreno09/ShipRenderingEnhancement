#ifndef VESSELAPI_H
#define VESSELAPI_H

#include <functional>
#include <QList>
#include "networking/BaseApi.h"
#include "entities/Vessel.h"

// ─── VesselApi ────────────────────────────────────────────────────────────────
// Fetches vessels from the simulator in two steps:
//   1. POST /simulation           → obtain a simulationId
//   2. GET  /simulation/:id/vessels → fetch the AIS vessel array
// Returns the parsed Vessel list via callback.

class VesselApi : public BaseApi
{
    Q_OBJECT

public:
    explicit VesselApi(HttpClient* client, QObject* parent = nullptr);

    void fetchAll(std::function<void(const QList<Vessel>&)> successCb,
                  ErrorCb errorCb);
};

#endif // VESSELAPI_H
