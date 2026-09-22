# Map pins round 2 (bd#221) — verification

Bilal's saved design-review selection: `fill:"even"`, `finish:"depth"`,
`label:"on"`, `numColor:"auto"`, `numScale:0.58`, `rim:"tone"`,
`size:"microplus"`, `weight:400`. Reference:
https://claude.ai/artifact/1gDVdnxqL1T51cVWQ3e8iF

Live-density screenshots (`bd-p2` simulator, iPhone 17 Pro, production
environment, fixed location `40.7335|-74.0027`, `manyVenues`-scale real
data) vs. the design-review mock's reference sheet.

Reference sheet: `selref-sheet.png` (also `selref-hood-dark.png`,
`selref-street-dark.png`, `selref-hood-light.png`, `selref-street-light.png`)

This PR's sheet: `p2-sheet.png` (also `p2-hood-dark.png`,
`p2-street-dark.png`, `p2-hood-light.png`, `p2-street-light.png`)

## Per-panel comparison

**Neighborhood, dark** (`p2-hood-dark.png` vs. `selref-hood-dark.png`)
- Gradient teardrops: yes — lightened top, darkened bottom, visible on every pin.
- Lighter rim: yes — a soft lighter-mint edge around every head.
- Numbers: Regular weight, near-black (`#08140F`), fully readable at every size.
- Low scores as bright as the reference: yes — `44`/`45`/`48` pins are the
  same bright mint as `84`, matching the "all bright" dark-map ramp.
- Names: "Think Coffee" (×2), "787 Coffee", "Joe Coffee Company", "Carmela
  Coffee" all render beside their pins, no overlap with pins, each other, or
  the search header/locate button.

**Street, dark** (`p2-street-dark.png` vs. `selref-street-dark.png`)
- Same fill/rim/number treatment at the larger street-zoom head size (18pt).
- More names visible at this zoom (12-label budget): "787 Coffee",
  "Stumptown", "The Coppola Cafe", "Caffe Reggio" — none overlapping the
  "Dante"/"Umeko" Apple POI markers or pins.

**Neighborhood, light** (`p2-hood-light.png` vs. `selref-hood-light.png`)
- Fill ramp unchanged from PR #218 (darkest = best): confirmed, `84`/`82`
  darkest green, `44`/`45` lighter.
- Numbers white, rim a lighter tint of each pin's own darker fill.
- Names: sage-green (`#1C5243`) with a white halo, legible over both light
  basemap fill and street lines.

**Street, light** (`p2-street-light.png` vs. `selref-street-light.png`)
- Same treatment at street zoom; labels for "787 Coffee", "Stumptown", "The
  Coppola Cafe", "Caffe Reggio" all legible, no overlaps.

## Bug found and fixed during verification

The first implementation rendered the name label via a SwiftUI `.overlay()`
extending past the pin's own declared frame. MapKit's `Annotation` measures
and rasterizes its content to the frame IT reports, so the overflowing
label was clipped/corrupted at render time (visible as a small black box
with garbled glyphs next to the pin, not real text). Fixed by making the
label a real `HStack` layout sibling of the pin (so the reported content
size actually includes it) and giving the `Annotation` a computed `anchor`
`UnitPoint` so the pin's tip still lands exactly on the venue's coordinate
instead of sliding sideways by roughly half the label's reserved width —
see `TeardropMarkerView.annotationAnchor(for:)`.

A second gap found in the same pass: a label beside a pin near the screen's
own left/right edge could render partly off-screen (clipped by the device
bezel). Fixed with a `labelScreenMargin` bounds check in
`MapAnnotationPlanner.placeNameLabels` (mirrors the design-review mock's
own `lx<6||lx+tw>W-6` guard).
