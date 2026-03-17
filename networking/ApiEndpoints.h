#ifndef APIENDPOINTS_H
#define APIENDPOINTS_H

#include <QString>

namespace ApiEndpoints {
    extern QString BaseUrl;

    QString Vessels();
    QString SimulationCreate();
    QString SimulationVessels(const QString& simulationId);
}

#endif // APIENDPOINTS_H
