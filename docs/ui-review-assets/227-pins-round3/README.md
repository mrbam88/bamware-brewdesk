# Pins round 3 (bd#227) — verification

TestFlight build 29 (PR #224, pins round 2) feedback from Bilal, with
screenshots: "Not really a tear shape??", "I see a weird box around
pins... really small", "in the dark mode we have to change the color...
it's hard to see." Light mode: "fine overall."

Live-density screenshots (`bd-p3` simulator, iPhone 17 Pro, production
environment, fixed location `40.7335|-74.0027`, real production data —
32-35 rated / 359 cafés in view).

- `p3-street-dark.png` / `p3-street-light.png` — 1.8 m/pt (street zoom, 18pt heads)
- `p3-hood-dark.png` / `p3-hood-light.png` — 3.6 m/pt (neighborhood zoom, 13.5pt heads)
- `p3-zoom-dark.png` / `p3-zoom-light.png` — 3x close-ups of the 787 Coffee /
  Partners Coffee / Stumptown cluster, both appearances

## Defect 1 — raster box

Root cause: `MarkerBodyImageCache`'s `ImageRenderer` canvas was sized
EXACTLY to the pin's own `diameter × frameHeight` box. The depth finish's
`.shadow(radius: 1.5, y: 1.5)` and 1pt rim stroke both paint a few points
beyond the shape's silhouette; `ImageRenderer` clips its output hard at the
content's proposed size, cutting the shadow's soft falloff off at a
rectangular edge instead of letting it fade to alpha 0 — that hard edge is
the "box," worst at the smallest sizes where the clip is a bigger fraction
of the whole pin.

Fix: `MarkerBodyShape` is rendered with 8pt of transparent `.padding()` on
every side before hitting the `ImageRenderer` canvas (`isOpaque = false`
was already set), so the shadow/stroke fully fade out before the raster
edge. `TeardropMarkerView.pinBody` composites the (now larger) cached image
via `Color.clear.overlay(Image(...))` instead of a bare `Image`, so the
extra padding bleeds outward from the pin's slot without changing what that
slot reports as its own size (the same established, already-shipped
pattern `selectedHalo` uses to bleed beyond its base view's bounds) —
`numberVerticalOffset`, `labelSlotWidth`, and `annotationAnchor(for:)` are
all untouched.

Verified: `MarkerBodyImageCacheTests.cachedRasterCornersAreFullyTransparent`
asserts alpha == 0 at all four raster corners, every numbered size stop,
both appearances. Visual: `p3-zoom-dark.png` / `p3-zoom-light.png` and the
extreme 6x single-pin crops (not committed, ephemeral) against plain
building/street background show no box/halo at any size, either appearance.

## Defect 2 — teardrop geometry

`TeardropShape`'s construction (rotated rounded-square, matching the mock's
own `border-radius: 50% 50% 50% 0; rotate(-45deg)` CSS) was already
mathematically correct — verified by hand: the sharp corner lands exactly
`side/√2 ≈ 0.7071·side` directly below the head center after rotation, for
a total frame height of `1.2071·diameter`, matching `tailHeightFactor
(1.21)`. The BLUNTED tip Bilal saw was the SAME raster-clip root cause as
Defect 1: the tip sits almost exactly at the canvas's bottom edge, so the
stroke's outer half-width and the shadow right at the tip were being
clipped too, rounding off what should read as a crisp point. The Defect 1
padding fix resolves both — visually confirmed in the zoom crops: every pin
now shows a full circular head and a sharp pointed tail.

## Defect 3 — dark-map fills too dim

`markerFillDarkMap` already held the exact approved mock values
(`#74C9A3/#86D9B3/#9BE8C4/#B4F5D6`, byte-identical) — Bilal explicitly
found even those hard to see on-device, so per the ticket this shifts one
step BRIGHTER than the mock rather than matching it:

| tier | old (= mock) | new |
|---|---|---|
| `<60` | `#74C9A3` | `#86D6B0` |
| `60-69` | `#86D9B3` | `#98E4C0` |
| `70-79` | `#9BE8C4` | `#ADF0D0` |
| `>=80` | `#B4F5D6` | `#C7F8E0` |

Pixel measurement (simulator screenshot, `p3-hood-dark.png`, a `52`-scored
tier-0 pin's head centre): sampled `(135,207,174)` / `(138,212,176)` /
`(135,202,170)` across three adjacent pixels vs. expected `#86D6B0` =
`(134,214,176)` — matches within compression/antialiasing tolerance.
`MarkerBodyImageCacheTests.darkMapRasterHeadCentreMatchesTheDarkRampNotTheLightRamp`
and `MarkerPaletteTests.darkMapMarkerFillMatchesTheBrighterThanMockRampExactly`
pin this in CI.

Numbers stay near-black (`#08140F`) — contrast against the brighter fills
only improves.

Also hardened (belt-and-suspenders, not the confirmed root cause — an
isolated raster-only unit test showed the OLD code already resolving the
correct dark-ramp color in this environment, so this didn't reproduce the
dimness on its own): `MarkerBodyImageCache`'s `ImageRenderer` has no public
API to force a trait collection for offscreen rendering, and this
package's `adaptive(light:dark:)` colors are built from a raw dynamic
`UIColor` provider (a deliberate bd#221 workaround for a real SwiftUI/iOS
26 threading crash — see that function's own doc comment). `MarkerBodyShape`
now takes an explicit `isDark: Bool` and reads new non-adaptive
`BrewDeskPalette` accessors instead of relying on ambient trait/environment
resolution at all, removing that class of risk regardless of device/OS
variance.

Light map: unchanged, confirmed via `p3-*-light.png`.

## Defect 4 — labels

**(a) Overlapping labels.** Root cause: the tightest gap the collision grid
ever guaranteed between two independently-placed teardrops
(`footprintPadding` → `diameter + 1`pt) can be LESS than `labelBoxHeight`
(14pt) at the smallest numbered size (12.5pt diameter → 13.5pt footprint).
Two such neighbours can both legitimately win teardrop slots while sitting
close enough that their label boxes clear the raw AABB check by under a
point — no visual gap once real font ascenders and `HaloText`'s doubled
2pt-radius blur are drawn. Fix: `placeNameLabels` now inflates the
CANDIDATE label rect by a new `labelCollisionMargin` (3pt) on every side
before testing against `grid`/`headBoxes` (a Minkowski-sum buffer; the rect
actually inserted stays the true, unpadded box, so this only adds real
spacing, never shrinks anyone else's legitimate placement).

**(b) Pin/label clipped at the screen edge.** Root cause: `plan()` is
deliberately NOT re-run on every camera delta — `CafeMapScreen.needsReplan`
skips replanning for a pan/zoom under 25% of the current span, by design
(perf). A label judged safely inside the old 6pt `labelScreenMargin` at
plan time can end up much closer to the device's FIXED screen edge after
one or more skipped-replan pans nudge the camera before the next real
replan. Fix: widened `labelScreenMargin` to 20pt — real slack against a
modest settle-drift pan. **Spec-gap decision:** this does not fully solve
the worst case (a full 25%-span drift, which would need either far more
frequent replanning — a perf regression — or live edge-clamping in the
view layer, both out of scope here); tracked, not silently dropped.

**(c) Label running into a neighbouring pin's head.** Already covered by
the existing `headBoxes` true-visual-head check from PR #224 round 2;
confirmed still holding under the new margins, and specifically verified
with "Caffe Reggio"/"82" — see `p3-hood-light.png` and `p3-hood-dark.png`,
where the label sits well clear of the `82` pin's head in both appearances
(the exact adjacency shown in the TestFlight screenshot no longer touches).

New planner tests (`MapAnnotationPlannerTests`), one per defect, each
verified to FAIL against the pre-fix constants before being confirmed
green against the fix:
`closelySpacedIndependentPinsGetVisiblyClearNonOverlappingLabels`,
`nameLabelNearTheRightEdgeIsOmittedRatherThanClipped`,
`namedRegressionCaffeReggioLabelNeverOverlapsTheEightyTwoPinsHead`.

## Kept unchanged from PR #224

Sizes (all stops), Regular numbers, tone rim, top-scored-first labels, 4pt
gap, 11pt semibold label font, light-map fill ramp.
