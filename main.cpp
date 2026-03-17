#include <QGuiApplication>
#include <QQmlApplicationEngine>

#include "networking/ApiEndpoints.h"
#include "networking/HttpClient.h"
#include "networking/VesselApi.h"
#include "models/VesselModel.h"

int main(int argc, char* argv[])
{
    QGuiApplication app(argc, argv);

    QCoreApplication::setOrganizationName("AIS");
    QCoreApplication::setApplicationName("MOC_ShipRenderingEnhancement");
    QCoreApplication::setApplicationVersion("1.0.0");

    QQmlApplicationEngine engine;

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.addImportPath("qrc:/");

    // ── Wire dependencies ─────────────────────────────────────────────────────
    auto* httpClient = new HttpClient(&app);
    auto* vesselApi  = new VesselApi(httpClient, &app);

    auto* vesselModel = engine.singletonInstance<VesselModel*>("MOC_ShipRenderingEnhancement", "VesselModel");
    vesselModel->initialize(vesselApi);

    // ── Launch ────────────────────────────────────────────────────────────────
    engine.loadFromModule("MOC_ShipRenderingEnhancement", "Main");

    return app.exec();
}
