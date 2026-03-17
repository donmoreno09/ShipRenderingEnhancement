import QtQuick 6.8
import QtQuick.Controls 6.8

import MOC_ShipRenderingEnhancement 1.0

ApplicationWindow {
    id: app
    width:   1280
    height:  800
    visible: true
    title:   "MOC Ship Rendering Enhancement"

    color: "#0d1117"

    MapPage {
        anchors.fill: parent
    }

    // Fetch vessels once the window is ready
    Component.onCompleted: VesselModel.fetch()
}
