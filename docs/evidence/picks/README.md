# Bamware Picks: what was seen

Signed Release build on an iPhone 17 simulator (iOS 27), fresh install, past
onboarding with `scripts/smoke/onboard.yaml`. Screenshots are half size.

Two fixture states, each in light and dark, from the scenario service
(`-UITestScenario onePick` and `tenPicks`). Every fixture café is named
"Fixture …" and every fixture line starts "Fixture line", so none of these
can be mistaken for a real list.

| State | Saved tab | Shelf card | Detail |
|---|---|---|---|
| 1 pick, nothing saved | `1-pick-{light,dark}-saved.png` | `1-pick-{light,dark}-shelf-card.png` | `1-pick-{light,dark}-detail.png` |
| 1 pick, one saved spot | `1-pick-with-saved-spot-light-saved.png` | | |
| 10 picks, top | `10-picks-{light,dark}-saved.png` | `10-picks-{light,dark}-shelf-card.png` | `10-picks-{light,dark}-detail.png` |
| 10 picks, rows 3 to 6 (unrated pick, saved pick, library) | `10-picks-{light,dark}-saved-rows-2-to-4.png` | `10-picks-{light,dark}-shelf-card-unrated-pick.png` | |
| 10 picks, bottom (140-character line, rank 10, earlier-year visit, then "Your saved spots") | `10-picks-{light,dark}-saved-bottom.png` | `10-picks-light-shelf-card-pick-10.png` (badge wraps under a long neighbourhood) | |

`10-picks-{light,dark}-saved-scrolled-title-collapsed.png` shows the list
scrolled: the large "Saved" title has collapsed into the bar and the
"Local only" line stays pinned under it. `no-picks-light-saved.png` is the
Saved tab when the engine serves no picks: as it was before the feature.

The Saved-tab shots were re-taken after a first round in which the large
"Saved" title was missing (the pinned line's background painted over it).

`production-{light,dark}-saved.png` is the same build against the production
engine, which began serving the real one-pick list while this was being
built.

The `.yaml` files are the Maestro flows that took the pictures.
