import QtQuick 6.8
import QtQuick.Controls 6.8
import QtLocation 6.8
import QtPositioning 6.8

import MOC_ShipRenderingEnhancement 1.0

// Full-screen map rendering AIS vessels with geo-anchored ship silhouettes.

Item {
    id: root

    Map {
        id: map
        anchors.fill: parent
        copyrightsVisible: true

        plugin: Plugin {
            name: "osm"
            PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
            PluginParameter { name: "osm.mapping.custom.host";                  value: "https://tile.openstreetmap.org/" }
        }

        center: QtPositioning.coordinate(44.0, 8.5)
        zoomLevel: 8
        minimumZoomLevel: 5
        maximumZoomLevel: 24

        // Scroll wheel zooms the map by 0.5 levels per notch.
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

        // Drag pans the map; translation is cumulative so we track the delta manually.
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

        // One MapQuickItem delegate per vessel row in VesselModel.
        MapItemView {
            model: VesselModel

            delegate: MapQuickItem {
                id: vesselItem

                // GPS latitude of the vessel's antenna — used as the map geo-anchor.
                required property double lat
                // GPS longitude of the vessel's antenna — used as the map geo-anchor.
                required property double lon
                // Compass heading the bow points (0°=North, clockwise). Falls back to COG when raw heading is 511 (unavailable).
                required property double displayHeading
                // Metres from antenna to Bow — determines how far the bow is from the GPS dot.
                required property int    a
                // Metres from antenna to Stern — together with A gives shipLength.
                required property int    b
                // Metres from antenna to Port (left side) — determines lateral antenna offset.
                required property int    c
                // Metres from antenna to Starboard (right side) — together with C gives shipWidth.
                required property int    d
                // Total hull length in metres (= A + B), computed in C++.
                required property int    shipLength
                // Total hull width in metres (= C + D), computed in C++.
                required property int    shipWidth
                // True when A/B/C/D are all non-zero; enables real-world sizing and correct antenna offset.
                required property bool   hasDimensions
                // Vessel name broadcast by the AIS transponder (e.g. "SIDER IBIZA").
                required property string name
                // Speed over ground in knots — declared for future use.
                required property double speed

                // Places the geo-anchor at the vessel's antenna GPS position.
                coordinate: QtPositioning.coordinate(lat, lon)

                // Show the vessel name label only when zoomed in enough to avoid clutter.
                readonly property bool showLabel: map.zoomLevel >= 15

                // Pin icon pixel size — shrinks from 48 px at zoom 5 to a minimum of 36 px.
                readonly property real pinSize: Math.max(48 - (map.zoomLevel - 5) * 1.5, 36)

                // Scaling factor that doubles every zoom level, matching how map resolution changes.
                // Calibrated so a 200 m ship ≈ 20 px at zoom 14. Avoids unreliable map.metersPerPixel.
                readonly property real zoomScale: Math.pow(2, map.zoomLevel - 14)

                // Raw pixel length/width from real-world metres. Capped to guard against bad AIS data (spec max is 511).
                readonly property real rawPxLength: hasDimensions ? Math.min(shipLength, 500) * zoomScale / 10 : 0
                readonly property real rawPxWidth:  hasDimensions ? Math.min(shipWidth,  80)  * zoomScale / 10 : 0

                // Minimum size that grows with zoom so ships without dimension data remain visible.
                readonly property real zf:         Math.max(map.zoomLevel - 10, 0)
                readonly property real minPxLength: 4 + zf * 2
                readonly property real minPxWidth:  2 + zf * 0.8

                // Final clamped pixel dimensions used to size the ship image.
                readonly property real pxLength: Math.min(Math.max(rawPxLength, minPxLength), 300)
                readonly property real pxWidth:  Math.min(Math.max(rawPxWidth,  minPxWidth),  60)

                // Pixel position of the antenna within the ship image (port→star, bow→stern).
                // Falls back to image center when hasDimensions is false.
                readonly property real antX: hasDimensions ? pxWidth  * (c / shipWidth) : pxWidth  / 2
                readonly property real antY: hasDimensions ? pxLength * (a / shipLength) : pxLength / 2

                // Half-diagonal of the ship bounding box — defines the square container that fits
                // the ship at any rotation. Also ensures room for the pin icon.
                readonly property real halfDiag: Math.ceil(Math.max(Math.sqrt(pxLength * pxLength + pxWidth * pxWidth), pinSize / 2 + 2))

                // Vector from the antenna to the ship image's geometric center (unrotated).
                readonly property real midOffX: pxWidth  / 2 - antX
                readonly property real midOffY: pxLength / 2 - antY

                // Heading in radians, including the +45° correction for the Figma SVG orientation.
                readonly property real headingRad: (displayHeading + 45) * Math.PI / 180

                // Screen position of the ship hull's visual center after rotation — where the pin is placed.
                readonly property real shipCenterX: halfDiag + midOffX * Math.cos(headingRad) - midOffY * Math.sin(headingRad)
                readonly property real shipCenterY: halfDiag + midOffX * Math.sin(headingRad) + midOffY * Math.cos(headingRad)

                // The center of the sourceItem square maps to the antenna GPS coordinate on screen.
                anchorPoint { x: halfDiag; y: halfDiag }

                sourceItem: Item {
                    width:  vesselItem.halfDiag * 2
                    height: vesselItem.halfDiag * 2

                    // Ship silhouette offset so the antenna pixel lands at the container center, then rotated around that same antenna pixel to stay geo-locked.
                    Image {
                        id: shipShape
                        x: vesselItem.halfDiag - vesselItem.antX
                        y: vesselItem.halfDiag - vesselItem.antY
                        width:  vesselItem.pxWidth
                        height: vesselItem.pxLength
                        source: "../assets/level-02.svg"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        transform: Rotation {
                            angle:    vesselItem.displayHeading + 45   // +45 corrects Figma SVG orientation
                            origin.x: vesselItem.antX // pivot at antenna, not image center
                            origin.y: vesselItem.antY
                        }
                    }

                    // Circle background stays centered on the hull midpoint.
                    Image {
                        id: pinCircle
                        x: vesselItem.shipCenterX - vesselItem.pinSize / 2
                        y: vesselItem.shipCenterY - vesselItem.pinSize / 2
                        width:  vesselItem.pinSize
                        height: vesselItem.pinSize
                        source: "../assets/circle-selection.svg"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        rotation: vesselItem.displayHeading + 45
                        z: 1
                    }

                    // Arrow icon rotates with heading on top of the circle.
                    Image {
                        id: pinIcon
                        x: vesselItem.shipCenterX - vesselItem.pinSize / 2
                        y: vesselItem.shipCenterY - vesselItem.pinSize / 2
                        width:  vesselItem.pinSize
                        height: vesselItem.pinSize
                        source: "../assets/Map_pin.svg"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        z: 2   // renders above the circle
                        rotation: vesselItem.displayHeading + 45
                        Behavior on rotation {
                            RotationAnimation { duration: 300; direction: RotationAnimation.Shortest }
                        }
                    }

                    // Vessel name label only shown at zoom ≥ 14, anchored below the antenna point.
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

    // HUD overlay — top-right panel showing zoom level, mode, and loading/error state.
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

    // Zoom +/- buttons — bottom-right corner, step by 1 level per click.
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
