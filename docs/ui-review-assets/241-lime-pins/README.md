# Dark-map lime pins, white rim, semibold numbers, tiny size — round 3 (bd#241)

Bilal's saved selection from the design-review page (round 3, 2026-09-25),
verbatim: fill `"lime"`, finish `"depth"`, label `"on"`, numColor `"auto"`,
numScale `0.58`, rim `"light"`, size `"tiny"`, weight `600` (Semibold).

Live-density screenshots (`bd-p4` simulator, iPhone 17 Pro, production
environment, fixed location `40.7335|-74.0027`, real production data —
15 rated / 359 cafés in view).

- `p4-hood-dark.png` / `p4-hood-light.png` — 3.6 m/pt (neighborhood zoom, 15pt heads)
- `p4-street-dark.png` / `p4-street-light.png` — 1.8 m/pt (street zoom, 20pt heads)
- `p4-zoom-dark.png` / `p4-zoom-light.png` — 4x close-ups of the 787 Coffee /
  Joe Coffee Company cluster, both appearances
- `p4-sheet.png` — all four tiled side by side
- `sel3ref-*.png` — Bilal's saved reference mock (same four panels, plus its
  own sheet), copied in from the design-review page for direct comparison

## Per-panel comparison against the references

**Street, dark (`p4-street-dark.png` vs `sel3ref-street-dark.png`)** — lime
fill on every pin, single hue, four lightness steps (dimmest ~37/66, brightest
~88/95). White 1pt rim on every pin, crisp against both the basemap and the
lime fill. Numbers read near-black and clearly semibold (the "88" close-up
below shows real stroke weight, not a thin/regular glyph). Heads read
noticeably larger than PR #229 (round 3's "microplus" 18pt street stop) —
matches the new "tiny" 20pt stop. Labels ("787 Coffee", "Joe Coffee Company",
"Stumptown", …) render in the same lime as the >=80 tier, with the dark halo
intact, so they read as one family with the pins as specified. No pin
overlaps; nothing renders under the search header or the shelf card.

**Hood, dark (`p4-hood-dark.png` vs `sel3ref-hood-dark.png`)** — same lime
ramp at the smaller 15pt "tiny" hood stop (up from round 3's 13.5pt
"microplus"). The four tiers are clearly distinguishable ("37" reads as a
darker olive-lime, "84/85/95" as the brightest yellow-lime), matching the
reference's tiering. White rim and near-black semibold numbers hold at the
smaller size too (verified with a close-up crop in the PR description).

**Street, light (`p4-street-light.png` vs `sel3ref-street-light.png`)** —
green ramp unchanged (`#1C5243`/`#2C6B58`/`#3D8069`), numbers white and
semibold, labels dark green (`#1C5243`) — all unchanged from PR #229 per
spec. The rim is now a flat white at 92% opacity rather than the previous
per-tier tone-mixed rim; visually very close to before (the old light-map
rim was already a light tint) but now pinned to the exact same value the
dark map uses. Heads are the larger "tiny" size on this map too.

**Hood, light (`p4-hood-light.png` vs `sel3ref-hood-light.png`)** — same as
above at the hood zoom; matches the reference.

## Pixel measurement (dark street shot)

`p4-street-dark.png`, the "88"-scored 787 Coffee pin (score 88, `>=80` tier,
expected fill `#C9FF3D` = `(201,255,61)`): head-centre region (screen coords
`x≈482, y≈950` in the 1206×2622 screenshot) sampled at `(482,964)` — just
below the number glyph, inside the head, before the tail — reads
`RGB(199,252,60)`, matching the expected top-tier lime within normal
antialiasing/gradient-finish tolerance (the "depth" finish's vertical
gradient is the plain fill only right at its 52% stop; a couple of points
off-center already picks up a touch of the top highlight/bottom shade).

## Contrast verification (near-black numbers on lime, all four tiers)

WCAG relative-luminance contrast of `#06120D` against each dark-map tier:

| tier | fill | contrast vs `#06120D` |
|---|---|---|
| `<60` | `#8FD214` | 10.36:1 |
| `60-69` | `#A3E61F` | 12.63:1 |
| `70-79` | `#B6F52A` | 14.62:1 |
| `>=80` | `#C9FF3D` | 16.23:1 |

All comfortably clear 4.5:1. Verified numerically in
`MarkerPaletteTests.darkMapMarkerNumberIsAlwaysNearBlack` and
`markerNumberColorClearsContrastAgainstItsOwnFillInBothAppearances`.

## Perf (Release, `ENABLE_TESTABILITY=YES`, `MapPerformanceUITests`, 3 runs)

| run | pinch-zoom hitchRatio (220 teardrops, tiny size) | dot-zoom hitchRatio |
|---|---|---|
| 1 | 0.1219 | 0.0818 |
| 2 | 0.1242 | 0.0671 |
| 3 | 0.1200 | 0.0696 |

All three runs stay under the 0.16 budget. The fill-color swap is free
(`MarkerBodyImageCache` still keys on tier index, not the literal hex), the
white rim is a flat constant (cheaper than the old per-tier `mix()` rim), and
the slightly bigger "tiny" heads cost a little — consistent with the ticket's
own expectation.

## Test counts

- **BrewDeskKit package tests** (`xcodebuild -scheme BrewDeskKit-Package`):
  all suites pass, 0 failures — including `MarkerPaletteTests` (10 tests, 3
  new: flat-white-rim, lime-ramp-exact, label-text-match) and
  `MapAnnotationPlannerTests` (updated size-stop assertions).
- **App build** (`BrewDesk` scheme, Debug and Release): zero new warnings.
- **UI suites** (Debug, one `-only-testing:` per command):
  `MapShelfDetentUITests` 5/5, `MapSearchAreaUITests` 3/3,
  `MapSearchAreaGPSRegressionUITests` 2/2, `SearchUITests` 11/11,
  `FilterUITests` 4/4 — all pass.
- **MapPerformanceUITests** (Release + `ENABLE_TESTABILITY=YES`): 4/4 pass,
  ×3 runs, hitchRatio table above.

## Spec-gap decisions

1. **Number weight, font choice.** The bundled `HankenGrotesk[wght].ttf` is
   a variable font whose `wght` axis genuinely spans 100–900 with a real
   "SemiBold" named instance at 600 (verified against the font's own `fvar`
   table) — so `markerNumber` now asks Hanken Grotesk for `.weight(.semibold)`
   directly, rather than falling back to the system font. This is a
   DIFFERENT code path from the bug `markerLabel`'s own doc comment records
   (a `.custom(_:fixedSize:).weight(...)` combo malforming a weight the
   face's `-Regular`-named static instance had to fake) — on-device the
   semibold numbers render cleanly (see `p4-zoom-dark.png` / `p4-zoom-light.png`),
   confirming the variable-font path works here and the fallback wasn't
   needed.
2. **Filter-menu legend.** The spec says demoted dots, specks, and the
   legend all "follow the same ramp." Demoted dots already do automatically
   (`BrewDeskPalette.markerFill(score:)`). Specks are left UNCHANGED and
   neutral — bd#159's rule ("never red/green, never tier-colored, an unrated
   venue has no score to tier by") predates and is orthogonal to this
   ticket; making specks tier-colored would contradict that established,
   tested rule (`MarkerPaletteTests.speckFillIsNeutralNeverTierColored`), so
   this is read as the ticket's shorthand for "everything that already
   colors by tier should share one ramp," not a request to retire the speck
   rule. The filter-menu legend's four swatches (`WorkFitFilterMenu
   .scoreLegend`) now source from `BrewDeskPalette.markerFill(score:)`
   instead of `ScoreTier.color`'s four-hue palette. Because the legend's own
   ranges (`75+/60-74/45-59/0-44`) don't align 1:1 with the marker ramp's
   four buckets (`<60/60-69/70-79/>=80`), the "mixed" (45-59) and "weak"
   (0-44) rows both land in the marker ramp's shared `<60` bucket and render
   the identical swatch color — an accurate reflection of the map itself (a
   50-scored and a 20-scored pin already render identically), not a defect
   in the legend.
3. **`closelySpacedIndependentPinsGetVisiblyClearNonOverlappingLabels`
   regression test.** Its original scenario (bd#227) depended on the
   smallest numbered stop's footprint (13.5pt) being just UNDER
   `labelBoxHeight` (14pt) — the new "tiny" smallest numbered stop (14pt
   diameter → 15pt footprint) no longer satisfies that. Rewrote the test to
   derive its mpp/diameter/footprint from the live planner constants at a
   slightly more-zoomed-out mpp (interpolated between the `9.0→4` and
   `5.4→14` stops) so the same near-miss condition is reconstructed
   generically rather than re-pinning a stale magic diameter — the
   underlying invariant (no visually-overlapping labels near a footprint/
   label-height near-miss) is unchanged and still covered.
