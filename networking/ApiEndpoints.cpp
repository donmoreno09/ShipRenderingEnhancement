#include "ApiEndpoints.h"

namespace ApiEndpoints {
    QString BaseUrl = "http://localhost:3000";

    QString Vessels()                              { return BaseUrl + "/vessels"; }
    QString SimulationCreate()                     { return BaseUrl + "/simulation"; }
    QString SimulationVessels(const QString& simulationId) { return BaseUrl + "/simulation/" + simulationId + "/vessels"; }
}
