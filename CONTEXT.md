# CONTEXT.md — BrewDesk domain terms

Quick-reference vocabulary for this repo. Not a tutorial — one line per term,
pointing at the source of truth.

- **LaunchEnvironment** — the one typed value every `-UITest*` /
  `-brewdesk.*` launch argument parses into (`VenueKit/LaunchEnvironment.swift`).
  Injected at app entry (`RootView`); no other module reads `ProcessInfo`
  directly.
- **Scenario** — `ScenarioVenueService.Scenario`: the deterministic fixture
  set (`engineDown`, `offline`, `fixtureOK`, …) a `-UITestScenario` launch
  selects, standing in for the live venue engine in UI and package tests.
- **StoreSurface** — the App Store submission build's accountless surface
  gate (Apple 1.2/5.1.1): hides accounts, report/block, and observation
  entry when `STORE_SURFACE_GATED=YES` or the UI-test override argument
  forces it on. One-directional — never turns a gated build's gate off.
- **Shelf detent** — the discovery map's honest resting positions (`peek`,
  `medium`, `full`) for the venue shelf overlay card; an in-tab alternative
  to a modal `.sheet` so the tab bar stays reachable at every detent.
- **Claim / Provenance** — a single fact about a venue (Wi-Fi speed, an
  amenity) carries its own `source` (curated / osm / estimate / speed_test /
  user_report / field_visit) and `confidence`, not a single trusted value —
  the engine's provenance model, mirrored 1:1 in `VenueKit/Models.swift`.
- **Venue / Workability score** — `Venue.workScore` (0–100) is the "can I
  work here" composite the engine computes from Wi-Fi, seating, noise, and
  outlet claims; `scoreTier` buckets it for the UI badge.

Cross-repo truth: github.com/mrbam88/bamware-ai (AGENTS.md, docs/contracts.md)
