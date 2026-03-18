import QtQuick 6.8
import QtQuick.Controls 6.8

import MOC_ShipRenderingEnhancement 1.0

ApplicationWindow {
    id: app
    width:   1280
    height:  800
    visible: true
    title: qsTr("MOC Ship Rendering Enhancement")

    MapPage {
        anchors.fill: parent
    }

    Component.onCompleted: VesselModel.fetch()
}
