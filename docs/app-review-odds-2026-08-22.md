# App Review odds audit — 2026-08-22

Baat died on 4.3(b) ("enough of these apps"). This is one honest pass on the
BrewDesk submission as a reviewer would see it, before more polish.

## 1. First 10 minutes — reviewer in California, store build

Store build = `STORE_SURFACE_GATED=YES` (accounts/report/block/observation OFF).
Steps mirror `docs/REVIEWER-SIMULATION.md`, which already runs this exact
scripted walkthrough in CI.

| Min | Action | What the reviewer sees | Risk hit |
| --- | --- | --- | --- |
| 0–1 | Fresh install, onboarding, decline location ("Use Union Square instead") | "Every score shows its work." → full NYC map, 100 work cafés | none |
| 1–3 | Browse Nearby, stat strip, Filters → Laptop-friendly, **type a search for "Housing Works"** | Results filter; search field | **bd#87**: keyboard cannot be dismissed after typing |
| 3–5 | Open Housing Works Bookstore Cafe detail | Workability section: source/confidence/date per claim, "Updated `<date>` · `<source>`" stamp | none — this is the differentiator |
| 5–6 | Tap methodology info button | "How Work Fit is scored" — full formula published in-app | none |
| 6–7 | Drag bottom sheet peek→medium→full | Visible flash on detent change | **bd#88** |
| 7–8 | Toggle dark mode (reviewer devices default to system appearance ~50% of the time) | Score-tier / destructive red text low contrast | **bd#89** |
| 8–9 | Grant location, simulated in California | `coverage-banner` "You're outside NYC — showing our NYC coverage." Map stays on NYC, 100 cafés — **does not go empty** | mitigated: **bd#1** (closed) — `VenuesModel.swift:96` `coverageRadiusM = 50_000.0` rejects out-of-coverage coordinates; `CafeMapScreen.swift:346-352` renders `coverage-banner` |
| 9–10 | Relaunch app | Tab bar reappears, no onboarding replay, dataset reloads | none |

Net: the walkthrough is clean on the concept and the out-of-coverage case, but
a reviewer typing one search query and dragging the sheet once will hit two
open bugs, and a dark-mode reviewer hits a third.

## 2. Differentiator visibility — binary AND listing

| Surface | Evidence | Visible? |
| --- | --- | --- |
| Binary — venue detail | `VenueDetailScreen.swift` Workability section: per-claim source, confidence, observation date; "Updated ⟨date⟩ · ⟨source⟩" stamp; human-verified seal | Yes |
| Binary — methodology | In-app "How Work Fit is scored" screen (weights, confidence blending, 90-day decay) | Yes |
| Listing — description | `fastlane/metadata/en-US/description.txt` leads with "Know why a café fits your workday" and a "SEE THE EVIDENCE" bullet section | Yes |
| Listing — screenshots | `fastlane/screenshots/en-US/01_evidence_not_ratings.png` is screenshot #1 (evidence-first, per `4.3-preflight.md`) | Yes, but **stale** — predates `#61` (clustered map) / `#62` (accent color, header glass) → **bd#68** |
| Review notes | `fastlane/review_information/notes.txt` gives the reviewer a literal script to reach the evidence (search "Housing Works" → Workability section → methodology) | Yes |

Differentiator is visible everywhere it needs to be. The one gap is that the
screenshot set (still evidence-first in content) shows an outdated UI shell.

## 3. Top 5 rejection risks, ranked by likelihood

| # | Risk | Guideline | Evidence | Fix | Ticket |
| --- | --- | --- | --- | --- | --- |
| 1 | 4.3(b) — "already enough of these apps" (Grounded, SpotGrove, Remoto listed as closest comps) | 4.3(b) | `fastlane/metadata/4.3-preflight.md`: "Guideline 4.3 risk remains high" | Differentiator is already the engine of the product (provenance + methodology), not a coat of paint — matches the field-notes advice ("reposition, don't polish"). Nothing left to build; confirm on the exact submitted build. | **bd#69** (reviewer dry-run) |
| 2 | 2.3.3 — screenshots don't match current UI | 2.3.3 | `bd#68`: screenshots predate `#61` (clustered map, merged `e19bd7d`) and `#62` (accent color/header glass, merged `1b61423`) | Rerun the `#30` screenshot pipeline against the store-build config | **bd#68** (existing, open) |
| 3 | 2.1 — performance/bugs a reviewer hits in the first 10 minutes | 2.1 | `bd#87` (search keyboard stuck), `bd#88` (bottom-sheet flash), `bd#89` (dark-mode red contrast) — all confirmed open, all on the reviewer-sim path | Fix all three before submission; they are the exact steps App Review's own reviewer will perform (search, drag sheet, default appearance) | **bd#87, bd#88, bd#89** (existing, open) |
| 4 | 5.1.1 — "Data Not Collected" privacy label vs. actual egress | 5.1.1 | `docs/PRIVACY-AUDIT.md` §Identifier: observation form sends a per-install `submittedBy` UUID to the engine — flagged "⚠ re-review before next store submission." Mitigated in the *store build* because `StoreSurface.isGated` hides the observation entry (`VenueDetailScreen.swift:42`), so the flow can't fire — but the label has not been formally re-affirmed against the gated build. | Re-run the App Privacy questionnaire against the actual store-build binary (not TestFlight) before submitting | **bd#31** (metadata finals — already scopes "questionnaires") |
| 5 | Location-denied / out-of-coverage map going empty (reviewer-critical, was Apple's literal Baat failure mode in spirit) | 2.1 / general usability | Largely mitigated: `bd#1` (closed) — `VenuesModel.swift:96` (`coverageRadiusM`), `CafeMapScreen.swift:346-352` (`coverage-banner`), covered by `VenuesModelPrivacyTests` and reviewer-sim step 6. Residual risk is unverified behavior on the *exact* submitted archive. | Confirm on the literal build going to App Review, not just CI/simulator | **bd#69** (reviewer dry-run) |

Not in the top 5 but checked: **1.2 UGC leakage** — low risk. Store build gates
report/block actions and community photo bylines off (`PhotoViewer.swift:89`,
`!StoreSurface.isGated`), and the observation form (only other UGC path) is
also gated off (`VenueDetailScreen.swift:42`). No UGC surface reaches the
store build.

## 4. Go/no-go and shortest path to Submit

**No-go today.** Three confirmed, reproducible bugs sit directly on the path
a reviewer will walk (search, sheet drag, dark mode), plus one confirmed-stale
screenshot set and one unresolved privacy-label re-check.

Shortest path to Submit, in order:

1. [ ] Fix **bd#87** (search keyboard stuck) — reviewer will type a search in minute 1–3.
2. [ ] Fix **bd#88** (bottom-sheet flash) — reviewer will drag the sheet.
3. [ ] Fix **bd#89** (dark-mode red contrast) — reviewer devices may default to dark.
4. [ ] Recapture screenshots — **bd#68** — against the current UI, store-build config.
5. [ ] Verify support/privacy URLs live and accurate — **bd#70**.
6. [ ] Re-run the App Privacy questionnaire against the gated store build — **bd#31**.
7. [ ] Run the reviewer dry-run on the exact submitted archive, California-simulated location — **bd#69**.
8. [ ] Assemble runbook + build 1.0(3) — **bd#33**.
9. [ ] Submit, with `docs/rejection-response-pack.md` (bd#32) ready in advance.

No app-code blockers beyond the three bug fixes above; everything else is
verification or asset regeneration.
