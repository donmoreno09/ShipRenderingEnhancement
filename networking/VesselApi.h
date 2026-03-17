#ifndef VESSELAPI_H
#define VESSELAPI_H

#include <functional>
#include <QList>
#include "networking/BaseApi.h"
#include "entities/Vessel.h"

// ─── VesselApi ────────────────────────────────────────────────────────────────
// Responsible for a single REST call: GET /vessels
// Returns the flat list of Vessel domain objects via callback.

class VesselApi : public BaseApi
{
    Q_OBJECT

public:
    explicit VesselApi(HttpClient* client, QObject* parent = nullptr);

    void fetchAll(std::function<void(const QList<Vessel>&)> successCb,
                  ErrorCb errorCb);
};

#endif // VESSELAPI_H
