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
- **Accounts** — sign in with Apple, Google, or email via the shared
  `BamwareAccounts`/`BamwareAccountUI` packages (`../bamware-ios`), composed
  for this tenant in `BrewDeskKit/AccountComposition.swift`
  (`BrewDeskAccountTenant`/`BrewDeskAccountStack`). Ships in every build,
  store submission included — bamware-brewdesk#174 (C9) retired the
  accountless `StoreSurface` gate brewdesk#67 introduced.
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
