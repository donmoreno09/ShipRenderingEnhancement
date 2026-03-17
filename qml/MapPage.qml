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

                // Geo anchor — the GPS coordinate is the antenna position
                coordinate: QtPositioning.coordinate(lat, lon)

                // ── Zoom threshold ───────────────────────────────────────────
                readonly property bool highZoom: map.zoomLevel >= 14

                // ── Ship pixel dimensions at current zoom ────────────────────
                // map.metersPerPixel converts real-world metres → screen pixels
                readonly property real pxLength: shipLength / map.metersPerPixel
                readonly property real pxWidth:  shipWidth  / map.metersPerPixel

                // ── Anchor offset compensation ───────────────────────────────
                // At high zoom: anchor the image so the antenna point (B from
                // stern = B/(A+B) from the top of the image when heading = 0°)
                // sits exactly on the coordinate.
                // At low zoom: centre the 57×57 icon on the coordinate.
                anchorPoint {
                    x: highZoom && hasDimensions
                        ? (pxWidth  * (c / Math.max(shipWidth,  1)))
                        : 57 / 2
                    y: highZoom && hasDimensions
                        ? (pxLength * (a / Math.max(shipLength, 1)))
                        : 57 / 2
                }

                sourceItem: Item {
                    width:  vesselItem.highZoom && vesselItem.hasDimensions ? vesselItem.pxWidth  : 57
                    height: vesselItem.highZoom && vesselItem.hasDimensions ? vesselItem.pxLength : 57

                    // ── Low-zoom icon ─────────────────────────────────────────
                    Image {
                        id: pinIcon
                        anchors.fill: parent
                        source: "qrc:/assets/Map_pin.svg"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        visible: !vesselItem.highZoom || !vesselItem.hasDimensions

                        rotation: vesselItem.displayHeading

                        Behavior on rotation {
                            RotationAnimation { duration: 300; direction: RotationAnimation.Shortest }
                        }
                    }

                    // ── High-zoom ship silhouette ─────────────────────────────
                    Image {
                        id: shipShape
                        anchors.fill: parent
                        source: "qrc:/assets/level-02.svg"
                        fillMode: Image.Stretch          // respect exact A/B/C/D proportions
                        smooth: true
                        visible: vesselItem.highZoom && vesselItem.hasDimensions

                        rotation: vesselItem.displayHeading

                        Behavior on rotation {
                            RotationAnimation { duration: 300; direction: RotationAnimation.Shortest }
                        }
                    }

                    // ── Vessel label (high zoom only) ─────────────────────────
                    Rectangle {
                        visible: vesselItem.highZoom
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 4
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
                text: map.zoomLevel >= 14
                    ? "▶ Ship silhouette mode"
                    : "▶ Icon mode  (zoom > 14)"
                color: map.zoomLevel >= 14 ? "#2ecc71" : "#888"
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
