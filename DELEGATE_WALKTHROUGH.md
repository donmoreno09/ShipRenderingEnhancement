# MapItemView Delegate — Step-by-Step Walkthrough

This document walks through every single property of the `MapQuickItem` delegate
using real vessel data. Every calculation is shown member by member until we reach
the final pixel position and rotation angle of each rendered element on screen.

---

## Vessel Used: ACCIARELLO at Zoom 17

```json
{
  "MMSI":      247106900,
  "NAME":      "ACCIARELLO",
  "LATITUDE":  42.93191,
  "LONGITUDE": 10.55631,
  "HEADING":   511,
  "COURSE":    341,
  "SPEED":     0,
  "A": 26,  "B": 87,  "C": 14,  "D": 5
}
```

**Map state used throughout this document:**
```
map.zoomLevel = 17
```

---

## STEP 1 — Required Properties (raw data from VesselModel)

These arrive directly from the C++ model. No calculation. Pure data.

```
lat           = 42.93191       → GPS latitude  of the antenna
lon           = 10.55631       → GPS longitude of the antenna
displayHeading = 341           → HEADING was 511 (unavailable), so C++ used COURSE=341 instead
a             = 26             → antenna is 26m from the Bow
b             = 87             → antenna is 87m from the Stern
c             = 14             → antenna is 14m from Port (left side)
d             = 5              → antenna is 5m  from Starboard (right side)
shipLength    = 113            → a + b = 26 + 87 = 113 metres total length
shipWidth     = 19             → c + d = 14 + 5  = 19  metres total width
hasDimensions = true           → shipLength > 0 AND shipWidth > 0
name          = "ACCIARELLO"   → vessel name to display in label
speed         = 0              → 0 knots (vessel is stationary)
```

```
Real-world ship layout (top view):

              BOW
               ▲
               │  26m (A)
               │
  14m (C) ─── ● ─── 5m (D)     ● = GPS antenna = (lat 42.93191, lon 10.55631)
               │
               │  87m (B)
               ▼
             STERN

  Total length = 26 + 87 = 113m
  Total width  = 14 + 5  = 19m
  Antenna is near the BOW and near the STARBOARD side.
```

> **Purpose:** These are the raw inputs the entire rendering system is built on.
> Without the real-world dimensions (A/B/C/D) there is no way to know how large
> the ship is, where to position the ship image, or where the GPS antenna sits
> inside the hull. Every subsequent calculation depends on these values.

---

## STEP 2 — coordinate

```qml
coordinate: QtPositioning.coordinate(lat, lon)
           = QtPositioning.coordinate(42.93191, 10.55631)
```

This is the GPS position of the antenna on Earth. Qt's map engine converts this
to a screen pixel position every frame. Everything else is rendered relative to
this point via the anchorPoint system.

> **Purpose:** This is the bridge between the real world and the screen. Without
> this, Qt has no idea where on the map to draw anything for this vessel. It is
> the single fixed reference point that all pixel positions are calculated from.

---

## STEP 3 — showLabel

```
showLabel = map.zoomLevel >= 14
          = 17 >= 14
          = true
```

The vessel name label will be visible at zoom 17.

> **Purpose:** Prevent the map from being cluttered with vessel names when zoomed
> out. At low zoom, many vessels are close together on screen and labels would
> overlap. Only show the name when the user has zoomed in far enough that each
> vessel occupies enough space to display a readable label.

---

## STEP 4 — pinSize

```
pinSize = Math.max(48 - (map.zoomLevel - 5) × 1.5,  36)
        = Math.max(48 - (17 - 5) × 1.5,  36)
        = Math.max(48 - 12 × 1.5,  36)
        = Math.max(48 - 18,  36)
        = Math.max(30,  36)
        = 36 px
```

The pin icon (circle + arrow) will be 36×36 px at zoom 17.
The minimum floor of 36 kicks in here — without it the result would be 30 px.

> **Purpose:** As you zoom in, the ship silhouette grows and dominates the screen.
> The pin icon shrinks proportionally so it doesn't overwhelm the hull shape at
> high zoom, while remaining large and visible at low zoom when the ship silhouette
> is too small to be meaningful. The floor of 36 px ensures the icon is always
> recognisable and never disappears.

---

## STEP 5 — zoomScale

```
zoomScale = Math.pow(2, map.zoomLevel - 14)
          = Math.pow(2, 17 - 14)
          = Math.pow(2, 3)
          = 8
```

At zoom 17 every real-world metre is 8× bigger in pixels compared to zoom 14.
This doubles every zoom step, matching how map tile resolution works physically.

> **Purpose:** This is the conversion factor between real-world metres and screen
> pixels. It must double every zoom level because that is exactly how OSM map
> tiles work — each zoom level doubles the number of tiles, halving the
> metres-per-pixel. Using this formula instead of `map.metersPerPixel` avoids
> the unreliable property that can return NaN during map initialisation.

---

## STEP 6 — rawPxLength and rawPxWidth

```
rawPxLength = Math.min(shipLength, 500) × zoomScale / 10.0
            = Math.min(113, 500) × 8 / 10.0
            = 113 × 8 / 10.0
            = 904 / 10.0
            = 90.4 px

rawPxWidth  = Math.min(shipWidth, 80) × zoomScale / 10.0
            = Math.min(19, 80) × 8 / 10.0
            = 19 × 8 / 10.0
            = 152 / 10.0
            = 15.2 px
```

Caps applied: shipLength=113 is well below 500, shipWidth=19 is well below 80.
So no capping happened here — raw AIS data used directly.

> **Purpose:** Translate the real-world hull dimensions from metres into screen
> pixels at the current zoom level. The `/10.0` is a calibration constant —
> a 200m ship should appear as ~20px at zoom 14, so dividing by 10 produces
> that ratio. The caps (500m, 80m) defend against corrupted AIS data where
> a device transmits the reserved value 511, which would otherwise produce an
> absurdly large ship image.

---

## STEP 7 — zf, minPxLength, minPxWidth

```
zf         = Math.max(map.zoomLevel - 10, 0)
           = Math.max(17 - 10, 0)
           = Math.max(7, 0)
           = 7

minPxLength = 4 + zf × 2
            = 4 + 7 × 2
            = 4 + 14
            = 18 px

minPxWidth  = 2 + zf × 0.8
            = 2 + 7 × 0.8
            = 2 + 5.6
            = 7.6 px
```

These minimums only matter for vessels with no dimension data (hasDimensions=false).
For ACCIARELLO they will be compared against rawPx values in the next step.

> **Purpose:** Guarantee that every vessel is always a visible shape on screen,
> even if A/B/C/D are all zero in the AIS data. Without a minimum, a vessel with
> no dimension data would render as a 0×0 invisible point. The minimum also grows
> with zoom (via `zf`) so that at high zoom levels, even unknown vessels appear as
> a reasonably sized shape rather than a 4px dot.

---

## STEP 8 — pxLength and pxWidth (final pixel dimensions)

```
pxLength = Math.min( Math.max(rawPxLength, minPxLength), 300 )
         = Math.min( Math.max(90.4, 18), 300 )
         = Math.min( 90.4, 300 )              ← rawPxLength wins over minimum
         = 90.4 px  →  90 px

pxWidth  = Math.min( Math.max(rawPxWidth, minPxWidth), 60 )
         = Math.min( Math.max(15.2, 7.6), 60 )
         = Math.min( 15.2, 60 )               ← rawPxWidth wins over minimum
         = 15.2 px  →  15 px
```

```
The ship image bounding box:

  ┌──────────────────┐  ← 15 px wide
  │                  │
  │                  │
  │                  │  90 px tall
  │                  │
  │                  │
  └──────────────────┘
```

> **Purpose:** Produce the final pixel size of the ship image by applying both
> a floor (so ships are never invisible) and a ceiling (so ships never fill the
> entire screen). This is a three-way clamp: the raw value from AIS data is the
> preferred result, but it is corrected upward if too small and downward if too
> large. Everything from this point forward uses pxLength and pxWidth.

---

## STEP 9 — antX and antY (antenna pixel inside the ship image)

```
antX = pxWidth  × (c / Math.max(shipWidth,  1))
     = 15.2     × (14 / Math.max(19, 1))
     = 15.2     × (14 / 19)
     = 15.2     × 0.7368
     = 11.2 px

antY = pxLength × (a / Math.max(shipLength, 1))
     = 90.4     × (26 / Math.max(113, 1))
     = 90.4     × (26 / 113)
     = 90.4     × 0.2301
     = 20.8 px
```

```
Where the antenna sits inside the ship image:

  ┌──────────────────┐  ← top = BOW
  │                  │
  │          ●(11,21)│  ← antenna at x=11.2, y=20.8
  │                  │     74% from left edge (near starboard)
  │                  │     23% from top edge  (near bow)
  │                  │
  │                  │
  │                  │
  │                  │
  └──────────────────┘  ← bottom = STERN
```

> **Purpose:** The GPS coordinate (lat/lon) is the antenna position, not the
> center of the ship. antX/antY translate that real-world offset into the
> equivalent pixel position inside the ship image. This is used for two things:
> (1) positioning the ship image so the antenna pixel lands exactly on the GPS
> coordinate on screen, and (2) setting the rotation pivot so the hull rotates
> around the antenna point, keeping the vessel perfectly geo-locked.

---

## STEP 10 — halfDiag (the rotation container radius)

```
halfDiag = Math.ceil(
               Math.max(
                   Math.sqrt(pxLength² + pxWidth²),
                   pinSize / 2 + 2
               )
           )

Step A — diagonal of ship bounding box:
  Math.sqrt(pxLength² + pxWidth²)
  = Math.sqrt(90.4² + 15.2²)
  = Math.sqrt(8172.16 + 231.04)
  = Math.sqrt(8403.2)
  = 91.67 px

Step B — minimum needed for pin icon:
  pinSize / 2 + 2
  = 36 / 2 + 2
  = 18 + 2
  = 20 px

Step C — take the larger:
  Math.max(91.67, 20) = 91.67 px

Step D — round up:
  Math.ceil(91.67) = 92 px

halfDiag = 92 px
```

```
The sourceItem square = halfDiag × 2 = 184 × 184 px

  ┌────────────────────────────────────────┐
  │             184 px wide                │
  │                                        │
  │                                        │
  │                ★ (92, 92)              │  ← antenna, always here
  │          halfDiag = 92 px              │
  │                                        │
  │                                        │
  └────────────────────────────────────────┘
  184 px tall

  The ship image (15×90) fits inside this square at any rotation angle
  because 92 ≥ half the diagonal (91.67) of the 15×90 rectangle.
```

> **Purpose:** When a rectangle rotates, its corners sweep outward. The maximum
> distance any corner can reach from the center equals half the diagonal of the
> rectangle. By making the sourceItem a square of side `halfDiag × 2`, the ship
> image can rotate to any heading without its corners ever going outside the
> container boundary — preventing visual clipping. It also guarantees room for
> the pin icon by checking `pinSize/2 + 2` as an alternative minimum.

---

## STEP 11 — midOffX and midOffY (vector from antenna to image center)

```
midOffX = pxWidth  / 2  -  antX
        = 15.2 / 2      -  11.2
        = 7.6            -  11.2
        = -3.6 px              ← center is 3.6 px to the LEFT of antenna

midOffY = pxLength / 2  -  antY
        = 90.4 / 2      -  20.8
        = 45.2           -  20.8
        = +24.4 px             ← center is 24.4 px BELOW the antenna
```

```
Inside the unrotated ship image:

  ┌──────────────────┐  ← BOW
  │                  │
  │          ●       │  ← antenna (11.2, 20.8)
  │         ↙        │
  │        ↙ (-3.6, +24.4) = midOff vector
  │                  │
  │                  │
  │      ○           │  ← image center (7.6, 45.2)
  │                  │
  └──────────────────┘  ← STERN

  ● = antenna     (the rotation pivot, always at screen position halfDiag,halfDiag)
  ○ = ship center (the point we need to track after rotation)
  ↙ = midOff      (the arrow FROM antenna TO center, before any rotation)
```

> **Purpose:** The pin icon must be placed at the visual center of the ship hull,
> but the hull rotates around the antenna — not its own center. To find where the
> center ends up after rotation, we first need to know how far and in what
> direction the center is from the antenna. That is exactly what midOffX/Y
> represent: the distance and direction from the pivot (antenna) to the target
> (hull center), expressed as a 2D vector. This vector is then rotated in the
> next steps.

---

## STEP 12 — headingRad (heading converted to radians)

```
headingRad = (displayHeading + 45) × Math.PI / 180
           = (341 + 45) × π / 180
           = 386 × π / 180
           = 386 × 0.017453
           = 6.737 rad

Note: 386° wraps around — same as 26° on the compass.
cos(26°) = 0.8988
sin(26°) = 0.4384
```

The `+45` is the correction for the Figma SVG being drawn 45° off North.
`× π/180` converts degrees to radians because Math.cos/sin require radians.

> **Purpose:** Math.cos() and Math.sin() only accept radians, but all heading
> data in AIS and QML rotation properties use degrees. This property converts
> the heading once and stores it so the same radians value can be reused in
> both the shipCenterX and shipCenterY calculations without repeating the
> conversion. The +45 is included here so the ship center tracking stays in
> sync with the actual rotation applied to the ship image.

---

## STEP 13 — shipCenterX and shipCenterY (final pin position)

This is where the midOff vector gets rotated by the heading.

```
shipCenterX = halfDiag  +  midOffX × cos(headingRad)  -  midOffY × sin(headingRad)
shipCenterY = halfDiag  +  midOffX × sin(headingRad)  +  midOffY × cos(headingRad)
```

**Breaking down shipCenterX member by member:**

```
Member 1:  halfDiag                        =  92       (antenna screen position, the starting point)
Member 2:  midOffX × cos(headingRad)       =  -3.6 × 0.8988  = -3.24  (horizontal component of rotated vector)
Member 3:  midOffY × sin(headingRad)       =  24.4 × 0.4384  = 10.70  (horizontal bleed from vertical rotation)

shipCenterX = 92 + (-3.24) - (10.70)
            = 92 - 3.24 - 10.70
            = 78.06 px  ≈  78 px
```

**Breaking down shipCenterY member by member:**

```
Member 1:  halfDiag                        =  92       (antenna screen position, the starting point)
Member 2:  midOffX × sin(headingRad)       =  -3.6 × 0.4384  = -1.58  (vertical bleed from horizontal rotation)
Member 3:  midOffY × cos(headingRad)       =  24.4 × 0.8988  = 21.93  (vertical component of rotated vector)

shipCenterY = 92 + (-1.58) + (21.93)
            = 92 - 1.58 + 21.93
            = 112.35 px  ≈  112 px
```

```
Final result inside the 184×184 sourceItem:

  ┌────────────────────────────────────────┐
  │                                        │
  │                                        │
  │          ● (92, 92)                    │  ← antenna — GPS point on map
  │           ↘                            │
  │            ↘  rotated midOff vector    │
  │             ↘                          │
  │              ○ (78, 112)               │  ← ship center — where pin goes
  │                                        │
  └────────────────────────────────────────┘

  The center is 14px left and 20px below the antenna,
  which matches the ACCIARELLO hull where the antenna
  is near the bow and near starboard — the geometric
  center of the hull is down and slightly to port.
```

> **Purpose:** This is the screen coordinate where the pin icon must be placed
> so it sits exactly at the visual center of the rotating ship hull. The ship
> rotates around the antenna, so the center orbits the antenna as heading changes.
> A simple fixed offset would only be correct at one specific heading. By applying
> the 2D rotation matrix (cos/sin) to the midOff vector, the correct center
> position is recalculated automatically every time the heading changes, keeping
> the pin always centered on the hull regardless of orientation.

---

## STEP 14 — anchorPoint

```
anchorPoint { x: halfDiag;  y: halfDiag }
           = { x: 92,       y: 92       }
```

Tells Qt's map: "the pixel at (92, 92) inside the sourceItem is the GPS point."
Qt places that pixel exactly at the screen position of coordinate (42.93191, 10.55631).

> **Purpose:** This is the geo-locking mechanism. Without anchorPoint, Qt would
> place the top-left corner of the sourceItem at the GPS coordinate, causing the
> entire vessel graphic to appear offset from its real position. By declaring
> (92, 92) as the anchor — which is also where the antenna pixel lands — we tell
> Qt to align the antenna pixel with the map coordinate. The vessel is then always
> drawn exactly where it physically is in the real world.

---

## STEP 15 — sourceItem dimensions

```
sourceItem width  = halfDiag × 2 = 92 × 2 = 184 px
sourceItem height = halfDiag × 2 = 92 × 2 = 184 px
```

Invisible container. All children are positioned inside this 184×184 square.

> **Purpose:** The sourceItem is the canvas that all visual children (ship shape,
> pin circle, pin arrow, label) are painted onto. It must be a square because the
> ship rotates in all directions, and a square of side `halfDiag × 2` is the
> smallest shape that guarantees the rotating ship never gets clipped. Its center
> (halfDiag, halfDiag) = (92, 92) is the antenna point, which becomes the single
> fixed reference for positioning every child element.

---

## STEP 16 — shipShape final position and rotation

```qml
Image {
    x: vesselItem.halfDiag - vesselItem.antX    →  92 - 11.2  =  80.8 px
    y: vesselItem.halfDiag - vesselItem.antY    →  92 - 20.8  =  71.2 px
    width:  vesselItem.pxWidth                  →  15.2 px
    height: vesselItem.pxLength                 →  90.4 px
    transform: Rotation {
        angle:    341 + 45                      →  386°  (= 26° effective)
        origin.x: vesselItem.antX               →  11.2 px  (pivot inside the image)
        origin.y: vesselItem.antY               →  20.8 px  (pivot inside the image)
    }
}
```

```
Before rotation:
  Ship image top-left corner is at (80.8, 71.2) in sourceItem.
  Antenna pixel (antX=11.2, antY=20.8) inside the image
  lands at (80.8+11.2, 71.2+20.8) = (92, 92) = halfDiag ✓

After rotation by 386° around (11.2, 20.8) within the image:
  The antenna pixel stays at (92, 92) — it is the pivot.
  The rest of the hull rotates around it.
  The bow, which was 20.8px above the antenna, swings to heading 26°.
```

> **Purpose:** Position and rotate the ship hull SVG so it is geo-locked to the
> real vessel position. The x/y offset places the image such that the antenna
> pixel inside the image coincides with the antenna GPS point on the map (92,92).
> The custom rotation origin ensures the hull rotates around that antenna pixel
> rather than around the image corner — this keeps the GPS position fixed on
> screen while the bow and stern sweep around it as heading changes.

---

## STEP 17 — pinCircle final position

```qml
Image {
    x: vesselItem.shipCenterX - vesselItem.pinSize / 2   →  78 - 18  =  60 px
    y: vesselItem.shipCenterY - vesselItem.pinSize / 2   →  112 - 18 =  94 px
    width:  36 px
    height: 36 px
    source: "circle-selection.svg"
    z: 1
    // no rotation
}
```

The circle background is centered at (78, 112) inside the sourceItem.
It does not rotate — a circle looks the same at any angle.

> **Purpose:** Provide the translucent blue circle background of the pin icon,
> centered on the visual midpoint of the ship hull. Subtracting `pinSize/2`
> converts from the center coordinate to the top-left corner that QML's x/y
> positioning expects. The circle does not rotate because rotating a circle
> produces no visible change — it is symmetric. It sits on z=1 so it renders
> above the ship silhouette but below the arrow.

---

## STEP 18 — pinIcon final position and rotation

```qml
Image {
    x:        60 px           (same as pinCircle — perfectly layered on top)
    y:        94 px
    width:    36 px
    height:   36 px
    source:   "Map_pin.svg"
    z:        2               →  above pinCircle and shipShape
    rotation: 341 + 45 = 386° (= 26° effective)
}
```

The arrow icon sits exactly on top of the circle, centered at (78, 112).
It rotates to heading 26° (341° actual heading + 45° SVG correction).

> **Purpose:** Render the directional arrow on top of the circle, pointing in
> the vessel's heading direction. It shares the same x/y as pinCircle so the
> arrow appears inside the circle. The plain `rotation` property (unlike
> `transform: Rotation`) rotates around the item's own center — which is already
> at shipCenterX/Y — so the arrow spins in place without drifting. z=2 ensures
> it renders on top of everything else. The RotationAnimation makes heading
> changes animate smoothly by the shortest arc rather than snapping instantly.

---

## STEP 19 — label final position

```qml
Rectangle {
    visible: true             (showLabel = true at zoom 17)
    x: halfDiag - width / 2  →  92 - (label width / 2)   ← centered on antenna horizontally
    y: halfDiag + 20          →  92 + 20 = 112 px         ← 20px below the antenna
    text: "ACCIARELLO"
}
```

The label appears 20 px below the antenna point, horizontally centered on it.
Its width depends on the text — "ACCIARELLO" ≈ 80px wide, so x ≈ 92 - 40 = 52 px.

> **Purpose:** Display the vessel name at a predictable, stable position that
> does not move with the ship's heading. Anchoring to the antenna point
> (halfDiag, halfDiag) rather than the rotating hull center means the label
> stays fixed below the GPS coordinate regardless of which way the bow is
> pointing. The +20 offset places it just below the vessel graphic without
> overlapping the ship shape or pin icon.

---

## Final Summary — All Elements at Zoom 17

```
sourceItem: 184 × 184 px invisible square

  Element       x        y       width  height  rotation  z
  ─────────────────────────────────────────────────────────
  shipShape     80.8     71.2    15.2   90.4    26°       0  (level-02.svg)
  pinCircle     60       94      36     36      none      1  (circle-selection.svg)
  pinIcon       60       94      36     36      26°       2  (Map_pin.svg)
  label         ~52      112     ~80    ~18     none      0  (visible: true)

  anchorPoint: (92, 92) = the antenna = GPS coordinate on the map
```

```
Visual layout inside sourceItem (not to scale):

  ┌──────────────────────────────────────────┐
  │                                          │
  │         ┌──┐                             │
  │         │  │ ship                        │
  │         │  │ image                       │
  │         │●─┤ ← antenna (92,92)           │
  │         └──┘                             │
  │          ◎  ← pin circle+arrow (78,112)  │
  │       ACCIARELLO  ← label (52,112)       │
  │                                          │
  └──────────────────────────────────────────┘
```

---

*ACCIARELLO · MMSI 247106900 · Zoom 17 · Heading 341° (COG)*
