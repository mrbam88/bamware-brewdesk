# Rejection response pack (bd#32)

Drafted 2026-08-22, companion to `docs/app-review-odds-2026-08-22.md` (bd#90).
Covers the audit's #1 risk (4.3(b)) and #2 risk (2.3.3 — stale screenshots).
**Nothing here is sent anywhere automatically — awaiting Bilal's tone
sign-off.** Strategy: submit → Resolution Center reply → App Review Board
appeal (reply first; appeal is the 4.3 escalation only). Before sending,
replace the `[QUOTE THE REJECTION TEXT]` slot with Apple's actual message and
re-verify every fact against the then-current build.

A near-identical draft (Replies for 4.3(b)/2.1/5.1 + appeal) already exists at
`bamware-ai/docs/rejection-response-pack.md` (2026-08-21) — this file reuses
its 4.3(b) reply and appeal verbatim-in-spirit, and adds a new reply for the
audit's #2 risk (2.3.3), which the bamware-ai draft doesn't cover.

---

## Reply 1 — Guideline 4.3(b) (design spam / saturated category)

> Thank you for reviewing BrewDesk. We believe the app offers a meaningfully
> different experience from existing café or map apps, and everything below
> is verifiable inside the submitted binary.
>
> BrewDesk is a work-fit measurement database for New York City with a map on
> top, not a café-review app. It evaluates NYC venues specifically for laptop
> work, and every individual claim — Wi-Fi, outlets, laptop policy, noise —
> displays its source, its confidence, and the date it was last updated,
> directly in the UI. To see this: search "Housing Works," open Housing Works
> Bookstore Cafe, and view the Workability section
> (`VenueDetailScreen.swift`).
>
> The complete scoring methodology is published inside the app ("How Work Fit
> is scored," reachable from the info button on Nearby): weights, confidence
> blending, and a 90-day freshness decay. Laptop policy is shown openly even
> when unflattering — venues that limit or discourage laptops are labeled,
> not hidden. Unknown values say "unknown"; estimates are labeled as
> estimates. This is also how the App Store listing describes the app (see
> the "SEE THE EVIDENCE" section of the app description).
>
> No widely available app does this. The most visible app in this space,
> Atly, places opinion-mined scores behind an annual subscription with no
> source, date, or methodology on any number [re-verify price before
> sending]. BrewDesk is free, accountless, and contains no purchases,
> subscriptions, advertising, analytics, or user-generated content.
>
> [QUOTE THE REJECTION TEXT and address its specific claim in one sentence.]
>
> We'd welcome guidance on anything specific the reviewer found
> indistinguishable — each differentiator above is a screen we can point to.
> Thank you for your time.

[BILAL: review tone]

---

## Reply 2 — Guideline 2.3.3 (screenshots don't match the app)

> Thank you for the review. On the screenshot concern: [QUOTE THE REJECTION
> TEXT and state which screenshot or claimed feature is in question.]
>
> We recaptured the full screenshot set against the exact store-build
> configuration before this submission — same map rendering, same accent
> color and header treatment, same UI shell as the reviewed binary. Screenshot
> 1 shows the venue-detail evidence view (per-claim source, confidence, date)
> because that is the app's primary function, followed by work filters and
> the Work Fit map, matching the order a user encounters them in the app.
>
> No screenshot shows a feature absent from this build: the store binary is
> accountless with the account entry, photo report/block actions, and the
> observation form all switched off (`STORE_SURFACE_GATED=YES`), and no
> screenshot depicts any of those surfaces.
>
> If a specific screenshot still looks inconsistent with what the reviewer
> sees on-device, we're glad to regenerate it immediately — our screenshot
> pipeline runs against the live production engine
> (https://venuekit-ashen.vercel.app) and can be rerun same-day.
>
> Thank you for flagging this so we can correct it precisely.

[BILAL: review tone]

---

## Appeal letter — 4.3(b) path

_Send only after a Resolution Center reply has failed. Keep the evidence list
intact — it is the argument._

> To the App Review Board,
>
> We are appealing the rejection of BrewDesk — WFH Cafés
> (`io.bamware.brewdesk`) under Guideline 4.3(b).
>
> Guideline 4.3(b) asks developers not to submit apps "indistinguishable from
> what's already widely available," and states that saturated categories will
> not accept new submissions "unless they offer a meaningfully different or
> improved experience." We believe BrewDesk meets that standard, on evidence
> visible in the submitted binary:
>
> 1. **Purpose.** BrewDesk answers one question — can I work from this café —
>    for a curated New York City venue dataset. It is a work-fit measurement
>    database with a map, not another restaurant-discovery app.
> 2. **Per-claim provenance.** Every Wi-Fi, outlet, laptop-policy, and noise
>    claim displays its source, confidence, and last-updated date in the UI.
>    Estimates are labeled; unknowns say "unknown."
> 3. **Published methodology.** "How Work Fit is scored" is a screen in the
>    app: the weights (laptop policy > seating > Wi-Fi = outlets > noise),
>    confidence blending, and 90-day freshness decay. No black-box scores.
> 4. **Transparency against interest.** Venues that limit or discourage
>    laptops are shown openly rather than omitted.
> 5. **Business-model contrast.** Widely available apps in this space sell
>    opinion-derived scores behind subscription paywalls. BrewDesk is free
>    and accountless, with no purchases, subscriptions, advertising,
>    analytics, or user-generated content.
>
> Each point can be confirmed in under a minute using the steps in our review
> notes (`fastlane/review_information/notes.txt`: search Housing Works
> Bookstore Cafe → Workability; info button → scoring methodology). We
> respectfully ask the Board to evaluate BrewDesk against the guideline's own
> test: a meaningfully different and improved experience, demonstrated in the
> binary rather than claimed in marketing.
>
> Thank you for your consideration.
>
> Bilal Malik
> Bamware

[BILAL: review tone]

---

## Fact sources

- Per-claim source/confidence/date, methodology screen, laptop-policy
  openness — `Packages/BrewDeskKit/Sources/BrewDeskKit/VenueDetailScreen.swift`,
  `fastlane/review_information/notes.txt`.
- Store-build gating (account/report-block/observation off) —
  `Packages/BrewDeskKit/Sources/BrewDeskKit/StoreSurface.swift`.
- Screenshot set and pipeline — `fastlane/screenshots/en-US/`; staleness
  finding — `docs/app-review-odds-2026-08-22.md` §3 risk 2 (bd#68).
- Guideline 4.3(b)/2.3.3 text and reply/appeal strategy —
  `bamware-ai/docs/app-review-field-notes.md`.
- Atly pricing/provenance contrast — `bamware-ai/docs/atly-teardown.md`
  (re-verify price before sending — it has changed before).
- Prior draft this reuses — `bamware-ai/docs/rejection-response-pack.md`
  (2026-08-21).
