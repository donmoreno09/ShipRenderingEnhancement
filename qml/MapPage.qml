import QtQuick 6.8
import QtQuick.Controls 6.8
import QtLocation 6.8
import QtPositioning 6.8

import MOC_ShipRenderingEnhancement 1.0

// ─── MapPage ──────────────────────────────────────────────────────────────────
// Full-screen map showing 5 AIS vessels.
//
// Zoom behaviour:
//   < 14  →  Map_pin.svg  (arrow icon, rotated by displayHeading)
//   ≥ 14  →  level-02.svg (ship silhouette, scaled by A/B/C/D in metres)
//
// The GPS coordinate is the antenna position, which sits at distance B from
// the stern and D from the starboard side. We compensate the anchor point
// inside the MapQuickItem so the image is geo-anchored correctly.

Item {
    id: root

    // ── Map ──────────────────────────────────────────────────────────────────
    Map {
        id: map
        anchors.fill: parent
        copyrightsVisible: true

        plugin: Plugin {
            name: "osm"
            PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
            PluginParameter { name: "osm.mapping.custom.host";                  value: "https://tile.openstreetmap.org/" }
        }

        center: QtPositioning.coordinate(44.0, 8.5)   // Ligurian Sea
        zoomLevel: 8
        minimumZoomLevel: 5
        maximumZoomLevel: 18

        // ── Pan & scroll interaction ──────────────────────────────────────────
        WheelHandler {
            id: wheel
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                const delta = event.angleDelta.y / 120
                map.zoomLevel = Math.min(map.maximumZoomLevel,
                                Math.max(map.minimumZoomLevel,
                                         map.zoomLevel + delta * 0.5))
            }
        }

        DragHandler {
            id: drag
            target: null
            property point lastTranslation: Qt.point(0, 0)
            onActiveChanged: if (active) lastTranslation = Qt.point(0, 0)
            onTranslationChanged: {
                map.pan(lastTranslation.x - translation.x, lastTranslation.y - translation.y)
                lastTranslation = translation
            }
        }

        // ── Vessel delegates ─────────────────────────────────────────────────
        MapItemView {
            model: VesselModel

            delegate: MapQuickItem {
                id: vesselItem

                required property double lat
                required property double lon
                required property double displayHeading
                required property int    a
                required property int    b
                required property int    c
                required property int    d
                required property int    shipLength
                required property int    shipWidth
                required property bool   hasDimensions
                required property string name
                required property double speed

                coordinate: QtPositioning.coordinate(lat, lon)

                // ── Zoom zones ───────────────────────────────────────────────
                //   always → pin icon (shrinks) + ship shape (grows)
                //   ≥ 14   → label also visible
                readonly property bool showLabel: map.zoomLevel >= 14

                // Pin icon shrinks from 48 px at zoom 5 down to 36 px at zoom 14+
                readonly property real pinSize: Math.max(48 - (map.zoomLevel - 5) * 1.5, 36)

                // ── Continuous size: zoom-level formula ──────────────────────
                // Avoids dependence on map.metersPerPixel (unreliable during
                // tile provider changes / map init).
                //
                // zoomScale doubles every zoom step — physically accurate since
                // metersPerPixel also halves every step.
                // Reference: a 200 m ship ≈ 20 px at zoom 14 (Mediterranean).
                //
                // Minimum grows with zoom so ships are always a visible shape.
                // Maximum clamps bad AIS data (A/B up to 511 in the spec).
                readonly property real zoomScale: Math.pow(2, map.zoomLevel - 14)

                readonly property real rawPxLength: hasDimensions
                    ? Math.min(shipLength, 500) * zoomScale / 10.0 : 0
                readonly property real rawPxWidth: hasDimensions
                    ? Math.min(shipWidth,  80)  * zoomScale / 10.0 : 0

                readonly property real zf:         Math.max(map.zoomLevel - 10, 0)
                readonly property real minPxLength: 4 + zf * 2
                readonly property real minPxWidth:  2 + zf * 0.8

                readonly property real pxLength: Math.min(Math.max(rawPxLength, minPxLength), 300)
                readonly property real pxWidth:  Math.min(Math.max(rawPxWidth,  minPxWidth),  60)

                // ── Antenna position inside the ship image ────────────────────
                readonly property real antX: hasDimensions
                    ? pxWidth  * (c / Math.max(shipWidth,  1))
                    : pxWidth  / 2
                readonly property real antY: hasDimensions
                    ? pxLength * (a / Math.max(shipLength, 1))
                    : pxLength / 2

                // sourceItem square: big enough for ship rotation AND pin icon
                readonly property real halfDiag: Math.ceil(
                    Math.max(Math.sqrt(pxLength * pxLength + pxWidth * pxWidth),
                             pinSize / 2 + 2))

                // ── Visual centre of the ship hull after rotation ─────────────
                // The ship image midpoint in local coords: (pxWidth/2, pxLength/2)
                // Offset from antenna (the rotation pivot at halfDiag,halfDiag):
                readonly property real midOffX: pxWidth  / 2 - antX
                readonly property real midOffY: pxLength / 2 - antY
                readonly property real headingRad: displayHeading * Math.PI / 180
                // Rotate that offset by heading → gives where midship lands in sourceItem
                readonly property real shipCenterX: halfDiag
                    + midOffX * Math.cos(headingRad) - midOffY * Math.sin(headingRad)
                readonly property real shipCenterY: halfDiag
                    + midOffX * Math.sin(headingRad) + midOffY * Math.cos(headingRad)

                // anchorPoint = centre of sourceItem = antenna GPS position
                anchorPoint {
                    x: halfDiag
                    y: halfDiag
                }

                sourceItem: Item {
                    width:  vesselItem.halfDiag * 2
                    height: vesselItem.halfDiag * 2

                    // ── Ship silhouette (always rendered, grows with zoom) ─────
                    // Offset so the antenna (antX, antY) lands at the centre of
                    // the sourceItem. Rotation pivots around that same point,
                    // keeping the pin locked on the coordinate.
                    Image {
                        id: shipShape
                        x: vesselItem.halfDiag - vesselItem.antX
                        y: vesselItem.halfDiag - vesselItem.antY
                        width:  vesselItem.pxWidth
                        height: vesselItem.pxLength
                        source: "../assets/level-02.svg"
                        fillMode: vesselItem.hasDimensions ? Image.Stretch : Image.PreserveAspectFit
                        smooth: true
                        transform: Rotation {
                            angle:    vesselItem.displayHeading
                            origin.x: vesselItem.antX
                            origin.y: vesselItem.antY
                        }
                    }

                    // ── Pin icon (always rendered, shrinks with zoom) ──────────
                    // Centred on the ship hull's geometric midpoint; rotates with heading.
                    Image {
                        id: pinIcon
                        x: vesselItem.shipCenterX - vesselItem.pinSize / 2
                        y: vesselItem.shipCenterY - vesselItem.pinSize / 2
                        width:  vesselItem.pinSize
                        height: vesselItem.pinSize
                        source: "../assets/Map_pin.svg"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        z: 1
                        rotation: vesselItem.displayHeading + 45
                        Behavior on rotation {
                            RotationAnimation { duration: 300; direction: RotationAnimation.Shortest }
                        }
                    }

                    // ── Label (zoom ≥ 14) ─────────────────────────────────────
                    Rectangle {
                        visible: vesselItem.showLabel
                        x: vesselItem.halfDiag - width / 2
                        y: vesselItem.halfDiag + 20
                        color: "#CC0d1117"
                        radius: 4
                        width: nameLabel.implicitWidth + 10
                        height: nameLabel.implicitHeight + 4
                        Text {
                            id: nameLabel
                            anchors.centerIn: parent
                            text: vesselItem.name
                            color: "#B1BAFF"
                            font.pixelSize: 10
                            font.family: "monospace"
                        }
                    }
                }
            }
        }
    }

    // ── HUD overlay ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.top:   parent.top
        anchors.right: parent.right
        anchors.margins: 16
        width:  200
        height: hudCol.implicitHeight + 20
        radius: 8
        color:  "#CC0d1117"
        border.color: "#B1BAFF"
        border.width: 1

        Column {
            id: hudCol
            anchors.centerIn: parent
            spacing: 6
            padding: 4

            Text {
                text: "AIS VESSELS"
                color: "#B1BAFF"
                font.pixelSize: 11
                font.family: "monospace"
                font.letterSpacing: 2
            }

            Rectangle { width: 180; height: 1; color: "#333355" }

            Text {
                text: "Zoom: " + map.zoomLevel.toFixed(1)
                color: "#8899cc"
                font.pixelSize: 10
                font.family: "monospace"
            }

            Text {
                text: map.zoomLevel >= 14 ? "▶ Detail mode"
                    : map.zoomLevel >= 11 ? "▶ Shape mode"
                                          : "▶ Icon mode"
                color: map.zoomLevel >= 11 ? "#2ecc71" : "#888"
                font.pixelSize: 10
                font.family: "monospace"
            }

            Rectangle { width: 180; height: 1; color: "#333355" }

            // Loading / error state
            Text {
                visible: VesselModel.loading
                text: "Loading vessels…"
                color: "#888"
                font.pixelSize: 10
                font.family: "monospace"
            }

            Text {
                visible: VesselModel.error !== ""
                text: "⚠ " + VesselModel.error
                color: "#e74c3c"
                font.pixelSize: 10
                font.family: "monospace"
                wrapMode: Text.WordWrap
                width: 180
            }
        }
    }

    // ── Zoom controls ─────────────────────────────────────────────────────────
    Column {
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        spacing: 2

        Rectangle {
            width: 36; height: 36; radius: 6
            color: "#CC0d1117"
            border.color: "#B1BAFF"; border.width: 1

            Text { anchors.centerIn: parent; text: "+"; color: "#B1BAFF"; font.pixelSize: 18 }

            MouseArea {
                anchors.fill: parent
                onClicked: map.zoomLevel = Math.min(map.maximumZoomLevel, map.zoomLevel + 1)
            }
        }

        Rectangle {
            width: 36; height: 36; radius: 6
            color: "#CC0d1117"
            border.color: "#B1BAFF"; border.width: 1

            Text { anchors.centerIn: parent; text: "−"; color: "#B1BAFF"; font.pixelSize: 18 }

            MouseArea {
                anchors.fill: parent
                onClicked: map.zoomLevel = Math.max(map.minimumZoomLevel, map.zoomLevel - 1)
            }
        }
    }
}
