# MOC Ship Rendering Enhancement — Technical Documentation

---

## 1. Project Overview

This is a Qt6/QML desktop application that connects to a local **VesselFinder-Simulator** (Express.js + MongoDB) and renders AIS vessel data on an interactive OpenStreetMap. The core challenge — and the name of the project — is **ship rendering enhancement**: displaying realistic, geo-anchored, correctly-rotated ship silhouettes that grow and shrink with zoom level.

---

## 2. Application Startup — Execution Flow

### Step 1 — `main.cpp`

```
app starts
  → QGuiApplication created
  → QQmlApplicationEngine created
  → HttpClient instantiated     (handles all HTTP with retry logic)
  → VesselApi instantiated      (uses HttpClient, knows the API endpoints)
  → VesselModel singleton retrieved from the QML engine
  → vesselModel->initialize(vesselApi)   (wires API into the model)
  → engine loads Main.qml
  → app.exec() — event loop begins
```

`main.cpp` is the wiring point. It creates the objects in C++, injects them into each other (dependency injection), and hands `VesselModel` to QML as a singleton so QML never has to create or own C++ objects.

---

### Step 2 — `Main.qml`

```qml
ApplicationWindow {
    MapPage { anchors.fill: parent }
    Component.onCompleted: VesselModel.fetch()
}
```

Once the window finishes loading (`Component.onCompleted`), it calls `VesselModel.fetch()`. This is the trigger that starts the entire data pipeline. The window is 1280×800 and hosts `MapPage` full-screen.

---

### Step 3 — `VesselModel.fetch()` (C++)

```
VesselModel::fetch()
  → sets loading = true  (QML HUD shows "Loading vessels…")
  → calls VesselApi::fetchAll(successCallback, errorCallback)
```

`VesselModel` is a `QAbstractListModel` singleton. It holds a `QVector<Vessel>` internally. QML never accesses `Vessel` objects directly — it only reads named roles through the model.

---

### Step 4 — `VesselApi::fetchAll()` — Two-Step HTTP Flow

```
POST /simulation
  → response: { simulationId: "abc123" }

GET /simulation/abc123/vessels
  → response: [ { AIS: { MMSI, NAME, LATITUDE, ... } }, ... ]
```

This is a two-step API because the simulator requires a simulation session before serving vessel data. The `simulationId` from step 1 is used to build the URL for step 2.

**Classes involved:**

| Class | Role |
|---|---|
| `HttpClient` | Low-level HTTP: builds requests, handles retries (exponential backoff), wraps Qt's `QRestAccessManager` |
| `BaseApi` | Helper templates: `expectObject()`, `expectArray()` — parses JSON and calls the callback or the error callback |
| `VesselApi` | Orchestrates the two-step flow, calls `vessel.fromAIS()` on each entry |
| `ApiEndpoints` | Central place for URL strings — `SimulationCreate()`, `SimulationVessels(id)` |

**Retry policy (HttpClient):** GET requests automatically retry on network errors and HTTP 408/429/500/502/503/504 with exponential backoff (200ms base, 2× multiplier, 5s max, 3 attempts).

---

### Step 5 — `Vessel::fromAIS()` — Data Parsing

```cpp
void fromAIS(const QJsonObject& ais) {
    mmsi    = ais["MMSI"].toInt();
    name    = ais["NAME"].toString();
    lat     = ais["LATITUDE"].toDouble();
    lon     = ais["LONGITUDE"].toDouble();
    heading = ais["HEADING"].toInt();
    cog     = ais["COURSE"].toDouble();
    displayHeading = (heading == 511) ? cog : static_cast<double>(heading);
    a = ais["A"].toInt();   b = ais["B"].toInt();
    c = ais["C"].toInt();   d = ais["D"].toInt();
}
```

The `511` check is important: in the AIS specification, heading value `511` means **unavailable**. When that happens, we fall back to COG (Course Over Ground) as the display direction. This is computed once here in C++ so QML never has to think about it.

---

### Step 6 — Back in `VesselModel` — Model Reset

```cpp
m_api->fetchAll([this](const QList<Vessel>& vessels) {
    beginResetModel();
    m_vessels = QVector<Vessel>(vessels.begin(), vessels.end());
    endResetModel();
    setLoading(false);
    emit fetched();
}, ...);
```

`beginResetModel()` / `endResetModel()` is the Qt signal that tells all connected QML views: "throw away everything and rebuild." This causes `MapItemView` in `MapPage.qml` to destroy all existing delegates and create new ones — one per vessel.

---

## 3. MapPage.qml — Complete Deep Dive

---

### 3.1 What is a Delegate?

`MapItemView` + `delegate` works like a `for` loop driven by the model. Qt creates **one live instance of the delegate for every row** in `VesselModel`. If there are 5 vessels, there are 5 `MapQuickItem` objects active on the map simultaneously. When the model resets (new data arrives), all delegates are destroyed and recreated.

```
VesselModel (C++ QAbstractListModel)
  row 0  →  MapQuickItem instance #0  (vessel: SIDER IBIZA)
  row 1  →  MapQuickItem instance #1  (vessel: PORTO CHELI)
  row 2  →  MapQuickItem instance #2  (vessel: ...)
  ...
```

Each delegate instance is completely independent — it has its own properties, its own pixel sizes, its own rotation state.

---

### 3.2 Map Setup

```qml
Map {
    plugin: Plugin {
        name: "osm"
        PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
        PluginParameter { name: "osm.mapping.custom.host"; value: "https://tile.openstreetmap.org/" }
    }
    center: QtPositioning.coordinate(44.0, 8.5)
    zoomLevel: 8
    minimumZoomLevel: 5
    maximumZoomLevel: 19
}
```

| Property | Value | Meaning |
|---|---|---|
| `plugin name: "osm"` | OpenStreetMap | Qt's built-in tile map provider |
| `providersrepository.disabled: true` | Disabled | Prevents Qt from trying to auto-select a provider, forces our custom host |
| `osm.mapping.custom.host` | tile.openstreetmap.org | The actual tile server URL. Tiles are PNG images served at `/{zoom}/{x}/{y}.png` |
| `center` | 44.0°N, 8.5°E | Ligurian Sea — where the simulated vessels are located |
| `zoomLevel: 8` | Starting zoom | Wide Mediterranean view |
| `minimumZoomLevel: 5` | Continent scale | Minimum zoom allowed |
| `maximumZoomLevel: 19` | Street level | Maximum zoom (OSM tile servers go up to 19) |

---

### 3.3 Pan — DragHandler

```qml
DragHandler {
    target: null
    property point lastTranslation: Qt.point(0, 0)
    onActiveChanged: if (active) lastTranslation = Qt.point(0, 0)
    onTranslationChanged: {
        map.pan(lastTranslation.x - translation.x, lastTranslation.y - translation.y)
        lastTranslation = translation
    }
}
```

`target: null` — the handler tracks the mouse gesture but does NOT automatically move any QML item. We take full control.

The `translation` property from `DragHandler` is **cumulative**: it keeps growing from (0,0) as long as the drag is happening. We need the delta between two frames, not the total:

```
Frame 1:  translation = (10, 5)   lastTranslation = (0, 0)
          delta = (0-10, 0-5) = (-10, -5) → pan map by (-10, -5)
          lastTranslation = (10, 5)

Frame 2:  translation = (18, 9)   lastTranslation = (10, 5)
          delta = (10-18, 5-9) = (-8, -4) → pan map by (-8, -4)
          lastTranslation = (18, 9)
```

`map.pan(dx, dy)` scrolls the map viewport by that many screen pixels.

---

### 3.4 Zoom — WheelHandler

```qml
WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: (event) => {
        const delta = event.angleDelta.y / 120
        map.zoomLevel = Math.min(map.maximumZoomLevel,
                        Math.max(map.minimumZoomLevel,
                                 map.zoomLevel + delta * 0.5))
    }
}
```

`angleDelta.y` is in "units" where 120 = one standard mouse wheel notch. Dividing by 120 gives notch count. `* 0.5` makes one notch = half a zoom level (smooth feel). `Math.min/Math.max` clamps within [5, 19].

---

### 3.5 MapItemView + MapQuickItem — The Geo-Rendering System

```
MapItemView
  └─ model: VesselModel          ← iterates over rows
     delegate: MapQuickItem      ← one per vessel
       coordinate: (lat, lon)    ← where on Earth to place it
       anchorPoint: (x, y)       ← which pixel of sourceItem sits at coordinate
       sourceItem: Item { ... }  ← the actual pixels drawn on screen
```

`MapQuickItem` is Qt's bridge between geographic coordinates and screen pixels. You give it:
- A GPS coordinate → Qt converts to screen XY every frame
- An anchorPoint → which pixel in your sourceItem aligns with that screen XY
- A sourceItem → any QML visual you want drawn there

---

### 3.6 Required Properties — Every One Explained

```qml
required property double lat
required property double lon
```
**GPS position of the vessel's antenna.** Not the center of the ship — the antenna. This is the raw coordinate from the AIS transponder. The `coordinate: QtPositioning.coordinate(lat, lon)` line binds this to the map's geo-anchor system.

```
          MAP (top = North)
          │
          │   ← this exact pixel on screen corresponds to (lat, lon)
          ●   ← the antenna
          │
```

---

```qml
required property double displayHeading
```
**The compass direction the bow points**, in degrees clockwise from North. 0° = North, 90° = East, 180° = South, 270° = West.

```
        0° (North)
        ↑
270° ←  ●  → 90°
        ↓
       180° (South)
```

This is a **resolved** value — if the raw AIS heading is `511` (meaning "sensor unavailable"), the C++ layer replaces it with COG (Course Over Ground) before it ever reaches QML. So `displayHeading` is always a usable number.

---

```qml
required property int a   // antenna → Bow      (metres)
required property int b   // antenna → Stern     (metres)
required property int c   // antenna → Port      (left,  metres)
required property int d   // antenna → Starboard (right, metres)
```

These four values describe where the GPS antenna sits on the physical ship hull. They come directly from the AIS transponder broadcast.

```
                     BOW (front of ship)
                          ▲
                          │
                    A metres│
                          │
     PORT ◄──── C metres──●──── D metres ────► STARBOARD
     (left)               │          GPS Antenna = (lat,lon)
                    B metres│
                          │
                          ▼
                    STERN (back of ship)
```

**Real example — a 200m cargo ship:**
- A = 160 m (antenna is 160 m from bow, i.e., near the stern)
- B = 40 m  (antenna is 40 m from stern)
- C = 10 m  (antenna is 10 m from port side)
- D = 20 m  (antenna is 20 m from starboard side)

Without these values, you could only place the ship image centered on the antenna. The ship's bow would appear 160 m behind its actual position on the map.

---

```qml
required property int shipLength   // = a + b
required property int shipWidth    // = c + d
```

The full physical dimensions of the hull in metres, computed in C++:
- `shipLength = A + B` = total length bow-to-stern
- `shipWidth  = C + D` = total width port-to-starboard

These drive the pixel size of the rendered ship image.

---

```qml
required property bool hasDimensions
```

`true` if `shipLength > 0 AND shipWidth > 0`. Some vessels broadcast A=B=C=D=0 (antenna offset not configured). When `hasDimensions` is false:
- Pixel sizes fall back to zoom-driven minimums
- `antX/antY` assume the antenna is at the image center
- `fillMode` stays `PreserveAspectFit` regardless

---

```qml
required property string name
```

The vessel's AIS name (e.g. `"SIDER IBIZA"`, `"PORTO CHELI"`). Displayed in the label at zoom ≥ 14. Can be empty for vessels that haven't broadcast their name.

---

```qml
required property double speed
```

Speed Over Ground in **knots**. Currently declared but not yet used in the visual rendering — reserved for future features (e.g. colour-coding fast vessels, animating movement).

---

### 3.7 Computed Properties — The Rendering Math

Every computed property (`readonly property`) is a **reactive binding** in QML. When any input changes (e.g. `map.zoomLevel` changes because the user scrolls), every property that depends on it automatically recalculates. There is no manual update loop.

---

#### `showLabel`

```qml
readonly property bool showLabel: map.zoomLevel >= 14
```

Simple threshold. At zoom 14 you're close enough that individual vessels are far apart on screen — showing names doesn't cause clutter.

---

#### `pinSize`

```qml
readonly property real pinSize: Math.max(48 - (map.zoomLevel - 5) * 1.5, 36)
```

Controls the pixel size of the `Map_pin.svg` icon. It shrinks linearly as you zoom in:

```
Zoom  5:  48 - (0)  × 1.5 = 48 px   (largest, low zoom, pin dominates)
Zoom  8:  48 - (3)  × 1.5 = 43.5 px
Zoom 11:  48 - (6)  × 1.5 = 39 px
Zoom 14:  48 - (9)  × 1.5 = 34.5 → clamped to 36 px
Zoom 19:  36 px  (minimum, ship silhouette is large and dominant)
```

`Math.max(..., 36)` is the floor — the pin never gets smaller than 36 px, so it remains recognisable at all zoom levels.

---

#### `zoomScale`

```qml
readonly property real zoomScale: Math.pow(2, map.zoomLevel - 14)
```

This is the **core formula** of the ship size system. It models the physical reality of how maps work:

> Each zoom level doubles the number of tiles — which means each pixel covers **half** the real-world distance. Therefore, a fixed-size real object appears **twice as large** on screen for every zoom step up.

`Math.pow(2, zoom - 14)` gives exactly that doubling behaviour, calibrated at zoom 14 = scale 1.0:

```
Zoom 11: 2^(11-14) = 2^(-3) = 0.125   →  ⅛ of zoom-14 size
Zoom 12: 2^(12-14) = 2^(-2) = 0.25    →  ¼ of zoom-14 size
Zoom 13: 2^(13-14) = 2^(-1) = 0.5     →  ½ of zoom-14 size
Zoom 14: 2^(14-14) = 2^(0)  = 1.0     →  reference size
Zoom 15: 2^(15-14) = 2^(1)  = 2.0     →  2× zoom-14 size
Zoom 17: 2^(17-14) = 2^(3)  = 8.0     →  8× zoom-14 size
Zoom 19: 2^(19-14) = 2^(5)  = 32.0    →  32× zoom-14 size
```

Why not use `map.metersPerPixel`? That property is unreliable — it can return 0 or NaN during map initialisation and tile provider switches, causing `NaN` to propagate into transforms and crash rendering.

---

#### `rawPxLength` / `rawPxWidth`

```qml
readonly property real rawPxLength: hasDimensions
    ? Math.min(shipLength, 500) * zoomScale / 10.0 : 0
readonly property real rawPxWidth: hasDimensions
    ? Math.min(shipWidth,  80)  * zoomScale / 10.0 : 0
```

Converts metres to pixels using `zoomScale`. The `/10.0` is the calibration constant: at zoom 14 (zoomScale=1), a 200m ship becomes 20 px. That matches real-world proportions in the Mediterranean at that zoom level.

`Math.min(shipLength, 500)` defends against bad AIS data. The AIS spec uses 511 as "value unavailable" for dimension fields — a ship claiming to be 511m long would be rendered absurdly large without this cap.

`Math.min(shipWidth, 80)` same protection for width — 80m is already an extremely wide vessel (supertanker class).

When `hasDimensions` is false, both return 0 so the minimum size formulas take over completely.

---

#### `zf`, `minPxLength`, `minPxWidth`

```qml
readonly property real zf:         Math.max(map.zoomLevel - 10, 0)
readonly property real minPxLength: 4 + zf * 2
readonly property real minPxWidth:  2 + zf * 0.8
```

`zf` (zoom factor) is zero below zoom 10, then grows 1 per zoom level above 10. It makes the **minimum visible size grow with zoom**:

```
Zoom  5:  zf=0  →  minLength=4px,  minWidth=2px   (tiny dots)
Zoom 10:  zf=0  →  minLength=4px,  minWidth=2px
Zoom 11:  zf=1  →  minLength=6px,  minWidth=2.8px
Zoom 14:  zf=4  →  minLength=12px, minWidth=5.2px
Zoom 19:  zf=9  →  minLength=22px, minWidth=9.2px
```

Without this, a vessel with no A/B/C/D data would show a 4px dot even at zoom 19 — too small to see. With `zf`, such vessels still grow into a visible shape as you zoom in.

---

#### `pxLength` / `pxWidth`

```qml
readonly property real pxLength: Math.min(Math.max(rawPxLength, minPxLength), 300)
readonly property real pxWidth:  Math.min(Math.max(rawPxWidth,  minPxWidth),  60)
```

These are the **final pixel dimensions** used to size the ship image. The formula is a double clamp:

```
pxLength = clamp(rawPxLength, min=minPxLength, max=300)

         rawPxLength=0        minPxLength        300
              │                    │               │
  ────────────●════════════════════●───────────────●────────
              uses minimum         uses raw         capped
```

The maximum cap of 300×60 px prevents ships with unusually large AIS dimensions from filling the entire screen at high zoom.

---

#### `antX` / `antY`

```qml
readonly property real antX: hasDimensions
    ? pxWidth  * (c / Math.max(shipWidth,  1))
    : pxWidth  / 2
readonly property real antY: hasDimensions
    ? pxLength * (a / Math.max(shipLength, 1))
    : pxLength / 2
```

Converts the real-world antenna offset into pixel coordinates **within the ship image**. Think of it as: what percentage of the ship's width/length does the antenna offset represent?

```
antX = pxWidth  × (C / shipWidth)
     = "C metres is what fraction of total width?" × "how wide is the image in pixels?"

antY = pxLength × (A / shipLength)
     = "A metres is what fraction of total length?" × "how tall is the image in pixels?"
```

Visual example — a ship with A=160, B=40, C=10, D=20 (shipLength=200, shipWidth=30):
```
  antX = pxWidth  × (10/30) = 0.33 × pxWidth   (antenna at 1/3 from port edge)
  antY = pxLength × (160/200) = 0.8 × pxLength  (antenna at 80% from bow = near stern)

  Ship image (pxWidth × pxLength):
  ┌──────────────────┐  ← bow (top of image)
  │                  │
  │                  │
  │                  │
  │                  │
  │                  │
  │                  │
  │      ●           │  ← antY = 80% down, antX = 33% from left
  │                  │     this pixel = GPS coordinate on the map
  └──────────────────┘  ← stern
```

`Math.max(..., 1)` prevents divide-by-zero when dimension data is missing.

---

#### `halfDiag`

```qml
readonly property real halfDiag: Math.ceil(
    Math.max(Math.sqrt(pxLength * pxLength + pxWidth * pxWidth),
             pinSize / 2 + 2))
```

When a rectangle rotates, its corners sweep out a circle. The radius of that circle is the **diagonal** of the rectangle divided by 2. `halfDiag` = that radius = the minimum distance from the center needed to guarantee the rotated rectangle fits.

```
Before rotation:           After rotation (45°):

  ┌──────────┐                  ╱╲
  │          │                ╱    ╲
  │    ●     │     →        ╱   ●   ╲
  │          │                ╲    ╱
  └──────────┘                  ╲╱

  The corners reach out to halfDiag distance from center ●
```

The `sourceItem` is a square of `halfDiag × 2` pixels. The ship image lives inside this square and can rotate freely without ever touching the edges.

`Math.max(..., pinSize/2 + 2)` ensures the square is also big enough to show the pin icon (which is `pinSize × pinSize` centered on the same point).

---

#### `anchorPoint`

```qml
anchorPoint {
    x: halfDiag
    y: halfDiag
}
```

This is the single most important property for correct geo-anchoring. It tells Qt's map engine:

> "The pixel at position `(halfDiag, halfDiag)` inside my `sourceItem` square corresponds to the GPS coordinate `(lat, lon)`. Place that exact pixel at the screen position of the coordinate."

```
sourceItem (halfDiag*2 × halfDiag*2 square):

  (0,0) ┌─────────────────────────────┐
        │                             │
        │                             │
        │                             │
        │           ★                 │  ← (halfDiag, halfDiag)
        │      anchorPoint            │     = GPS (lat,lon) on screen
        │                             │
        │                             │
        └─────────────────────────────┘ (halfDiag*2, halfDiag*2)

  The ship image is placed so its antenna pixel (antX, antY)
  lands exactly at ★. The whole sourceItem shifts so ★ sits
  on the map at the vessel's real GPS coordinates.
```

---

#### Ship silhouette Image

```qml
Image {
    id: shipShape
    x: vesselItem.halfDiag - vesselItem.antX
    y: vesselItem.halfDiag - vesselItem.antY
    width:  vesselItem.pxWidth
    height: vesselItem.pxLength
    source: "../assets/level-02.svg"
    fillMode: Image.PreserveAspectFit
    transform: Rotation {
        angle:    vesselItem.displayHeading + 45
        origin.x: vesselItem.antX
        origin.y: vesselItem.antY
    }
}
```

**`x` / `y` positioning:**
The ship image is offset inside the `sourceItem` square so that the antenna pixel `(antX, antY)` — within the ship image's own coordinate space — lands at the container's center `(halfDiag, halfDiag)`:

```
x = halfDiag - antX
    ↑ container center    ↑ antenna offset in image
    → positions image left so antenna column is at center

y = halfDiag - antY
    → positions image up so antenna row is at center
```

```
sourceItem square:
  ┌──────────────────────────────────┐
  │      ┌────────┐                  │
  │      │  ship  │                  │
  │      │ image  │                  │
  │      │        │                  │
  │      │   ★────┼──────────────────┼── halfDiag, halfDiag
  │      │(antX,Y)│                  │   GPS point
  │      └────────┘                  │
  └──────────────────────────────────┘
  x = halfDiag - antX  positions the image so ★ hits center
```

**`fillMode: Image.PreserveAspectFit`:**
The Figma SVG has its own aspect ratio (88:101). If we used `Image.Stretch`, the SVG would be squashed/stretched to fit `pxWidth × pxLength`, distorting the hull shape into an unrecognizable thin line. `PreserveAspectFit` scales the SVG uniformly to fit within the bounding box while preserving proportions.

**`transform: Rotation`:**
```qml
transform: Rotation {
    angle:    vesselItem.displayHeading + 45
    origin.x: vesselItem.antX
    origin.y: vesselItem.antY
}
```

This is different from the simple `rotation` property. `transform: Rotation` lets you specify a **custom pivot point** — here `(antX, antY)`, the antenna pixel within the image. This means the ship rotates **around the antenna point**, not around the image center. The GPS position on screen stays perfectly locked while the hull rotates around it.

`+ 45` corrects for the Figma SVG being drawn 45° off from North — without this, `displayHeading=0` would make the bow point NW instead of N.

```
Without custom origin (rotation around image center):
  The bow drifts away from the real GPS position
  as the ship rotates.  ✗

With origin at (antX, antY):
  The antenna point stays locked on the GPS coordinate
  no matter what heading the ship has.  ✓
```

---

#### Visual center calculation

```qml
readonly property real midOffX: pxWidth  / 2 - antX
readonly property real midOffY: pxLength / 2 - antY
readonly property real headingRad: (displayHeading + 45) * Math.PI / 180
readonly property real shipCenterX: halfDiag
    + midOffX * Math.cos(headingRad) - midOffY * Math.sin(headingRad)
readonly property real shipCenterY: halfDiag
    + midOffX * Math.sin(headingRad) + midOffY * Math.cos(headingRad)
```

The pin icon should sit at the **geometric center of the hull**, not at the antenna. But after rotation, we need to know where the center actually ends up on screen.

**Step 1 — midOffX/Y:** Vector from the antenna to the ship image's geometric center, in unrotated image coordinates:
```
midOffX = pxWidth/2  - antX   (horizontal: center minus antenna column)
midOffY = pxLength/2 - antY   (vertical:   center minus antenna row)
```

**Step 2 — headingRad:** Convert degrees to radians (required by `Math.cos`/`Math.sin`). Must include `+45` to match the ship transform.

**Step 3 — Apply 2D rotation matrix:**
```
After rotating the midpoint vector by headingRad:

  rotated_x = midOffX × cos(θ) - midOffY × sin(θ)
  rotated_y = midOffX × sin(θ) + midOffY × cos(θ)

shipCenterX = halfDiag + rotated_x   (halfDiag = antenna position in sourceItem)
shipCenterY = halfDiag + rotated_y
```

Visually:
```
Before rotation:            After rotation by θ:

  ★ = antenna (halfDiag,halfDiag)
  ○ = ship center

  ┌────────┐                      ╱────╲
  │   ○    │         →           ╱  ○   ╲
  │        │                     ╲  ★   ╱
  │   ★    │                      ╲────╱
  └────────┘

  midOffX/Y traces the ○→★ distance.
  The rotation matrix spins that vector.
  Adding halfDiag gives the final screen position of ○.
```

---

#### Pin icon Image

```qml
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
```

**`x/y`:** Centers the pin image on `(shipCenterX, shipCenterY)` — the ship hull's visual midpoint after rotation. Subtracting `pinSize/2` shifts from top-left corner to center.

**`z: 1`:** Renders the pin on top of the ship silhouette. Without this, the ship image would cover the pin.

**`rotation: displayHeading + 45`:** Unlike `transform: Rotation`, the plain `rotation` property rotates around the item's own center. Since the item is already centered at `shipCenterX/Y`, it rotates the arrow in place. `+45` is the same SVG correction as the ship shape.

**`Behavior on rotation / RotationAnimation.Shortest`:** When `displayHeading` changes (e.g. vessel updates position), instead of instantly snapping to the new angle, it animates over 300ms by the shortest arc:
```
Heading changes from 350° → 10°:
  Without Shortest: rotates -340° anti-clockwise  (long way around)  ✗
  With Shortest:    rotates  +20° clockwise        (short arc)        ✓
```

---

#### Label Rectangle

```qml
Rectangle {
    visible: vesselItem.showLabel      // only at zoom ≥ 14
    x: vesselItem.halfDiag - width / 2 // centered on antenna point
    y: vesselItem.halfDiag + 20        // 20 px below antenna point
    color: "#CC0d1117"                 // dark background, 80% opacity
    radius: 4                          // rounded corners
    width: nameLabel.implicitWidth + 10
    height: nameLabel.implicitHeight + 4
    Text {
        id: nameLabel
        anchors.centerIn: parent
        text: vesselItem.name
        color: "#B1BAFF"               // soft blue-white
        font.pixelSize: 10
        font.family: "monospace"
    }
}
```

The label is always anchored to the **antenna point** `(halfDiag, halfDiag)`, not to the ship's visual center. This keeps it in a predictable position below the vessel regardless of heading. It only appears at zoom ≥ 14 to avoid a cluttered map at wide zoom levels.

---

### 3.8 HUD Overlay

The top-right panel shows live state:

| Element | What it shows |
|---|---|
| `"AIS VESSELS"` | Static title |
| `Zoom: X.X` | Live zoom level with one decimal |
| Mode text | `Icon mode` (zoom < 11) / `Shape mode` (≥11) / `Detail mode` (≥14) |
| `Loading vessels…` | Visible only while `VesselModel.loading` is true |
| `⚠ error message` | Visible only when `VesselModel.error` is non-empty |

---

### 3.9 Zoom Buttons

Two `Rectangle` + `MouseArea` buttons in the bottom-right corner. They increment/decrement `map.zoomLevel` by exactly 1, clamped to the [5, 19] range. These are the click alternatives to the mouse wheel.

---

## 4. Summary — The "Magic" of Ship Rendering Enhancement

The rendering system solves five hard problems simultaneously:

| Problem | Solution |
|---|---|
| Ship must be geo-anchored at the GPS antenna position, not the image center | `anchorPoint` set to `(halfDiag, halfDiag)`. Ship image offset by `(halfDiag - antX, halfDiag - antY)` so its antenna pixel lands at the container center |
| Ship must rotate around the antenna, not the image center | `transform: Rotation` with `origin.x: antX, origin.y: antY` — rotates the image around the antenna pixel inside it |
| Ship must scale correctly with zoom using real-world metres | `zoomScale = 2^(zoom-14)` mirrors how map tile resolution doubles per zoom level, converting metres to pixels accurately without the unreliable `metersPerPixel` property |
| Pin icon must sit at the visual center of the rotated ship, not the antenna | 2D rotation matrix applied to the vector from antenna to ship image midpoint — accounts for the actual rotation angle including the +45° SVG correction |
| Both SVG assets drawn 45° off North in Figma | `+45` added to both the ship `transform: Rotation` angle and the pin `rotation` property as a fixed correction constant |

---

*Generated 2026-03-17 — MOC Ship Rendering Enhancement v1.0*
---

## 5. Summary — The "Magic" of Ship Rendering Enhancement

The rendering system solves three hard problems simultaneously:

| Problem | Solution |
|---|---|
| Ship must be geo-anchored at the GPS antenna position, not the image center | `anchorPoint` set to `(halfDiag, halfDiag)`, ship image offset by `(halfDiag - antX, halfDiag - antY)` so the antenna pixel is at the container center |
| Ship must rotate around the antenna, not the image center | `transform: Rotation` with `origin.x: antX, origin.y: antY` — rotates inside the image around the antenna pixel |
| Ship must scale correctly with zoom using real-world metres | `zoomScale = 2^(zoom-14)` mirrors how map tile resolution doubles per zoom level, converting metres to pixels accurately without relying on the unreliable `metersPerPixel` property |
| Pin icon must sit at the visual center of the rotated ship | 2D rotation math applied to the vector from antenna to ship midpoint, accounting for the rotation angle |
| SVG assets drawn at 45° offset from North in Figma | `+45` added to both ship transform and pin rotation as a fixed correction |

---

*Generated 2026-03-17 — MOC Ship Rendering Enhancement v1.0*
