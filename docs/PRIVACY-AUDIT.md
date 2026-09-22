# Privacy audit — what leaves the device

BrewDesk's App Privacy answer is **Data Not Collected**. This document is the
evidence behind it and the map to the automated tests that keep it true
(brewdesk#29). Re-read it whenever a network call, SDK, or analytics hook is
added.

## Egress inventory

The app has exactly one HTTP client, `VenueAPI`
(`Packages/BrewDeskKit/Sources/VenueKit/VenueAPI.swift`), pointed at the
venue engine (`https://venuekit-ashen.vercel.app` in Release). Everything it
can send:

| Flow | Request | Host | Location-bearing params |
| --- | --- | --- | --- |
| Map / Nearby list | `GET /v1/venues?sort&limit&radius_m[&filters]` + header `X-BrewDesk-Viewport: <lat>,<lng>` | engine | header only — the **map-query centre** (see below). Not in the URL. |
| Stat strip | `GET /v1/health` | engine | none |
| Detail | `GET /v1/venues/{id}` | engine | none |
| Photo strip / viewer (list) | `GET /v1/venues/{id}/photos` | engine | none |
| Photo strip / viewer (bytes) | `GET <photoUri>` via `AsyncImage` | `lh3.googleusercontent.com` | none — opaque Google photo URI, no place_id, no coordinates |
| Neighborhood chips | `GET /v1/neighborhoods` | engine | none |
| Import from Takeout | `GET /v1/venues?sort&limit=200&radius_m` | engine | none — no viewport header |
| *(not reachable in v1 UI)* speed test | `POST /v1/observations` `{venueId,kind,mbpsDown}`; probe `GET /v1/venues?limit&_speed_test_nonce` | engine | none — no viewport header |
| Rate this visit (observation form, brewdesk#47) | `POST /v1/venues/{id}/observations` `{submittedBy, answers:{laptopFriendlyToday,seatsAvailable,outletsWorking,noise}}` — enum values only, no free text | engine | none |

The complete URL query vocabulary `VenueQuery` can emit is
`sort limit radius_m wifi_min outlets_min minSeating venueType laptops
neighborhood q`. None of those names can carry a location. Coordinates travel
only as `X-BrewDesk-Viewport: <lat>,<lng>` (engine #16 / brewdesk#154). A test
fails if that split changes.

### What the viewport header contains

| Location state | Value sent | Why |
| --- | --- | --- |
| Not determined / **denied** / "Use Union Square instead" | `40.7359, -73.9911` — Union Square, the hardcoded coverage anchor (`VenuesModel.coverageCenter*`) | `LocationService.location` stays `nil`; the model never receives a device coordinate |
| Granted, **anywhere** (e.g. App Review in California) | the device coordinate, full precision | bd#108 removed the >50km-from-anchor rejection this table used to describe — the app now always queries the real viewport it was given, so real venues near a reviewer render instead of NYC's; sent to the engine only, used transiently to rank by proximity |

So a user who denies location never has a device coordinate leave the phone.
Once granted, the coordinate is sent regardless of distance from NYC — this
is a deliberate change from the pre-bd#108 behaviour (which used to discard
an out-of-coverage coordinate and re-query the anchor instead) and does not
change the **Data Not Collected** answer: the coordinate is used transiently
to rank one response and is never stored, associated with an identity, or
sent anywhere but the engine. This is asserted, not assumed
(`VenuesModelPrivacyTests`, `PrivacyClaimTests.fallbackQueryTargetsUnionSquareNotTheDevice`).

### Identifier: per-install submitter id (brewdesk#47) — ⚠ re-review before next store submission

The observation form sends `submittedBy`: a random UUID minted on device on
first submit and stored in UserDefaults (`brewdesk.observation.submitter-id`,
covered by the already-declared CA92.1 UserDefaults reason). It is not an OS
identifier (not IDFA/IDFV), carries no personal data, and leaves the device
only inside an observation submit — but it IS a stable per-install identifier
reaching the engine. The **"Data Not Collected"** App Privacy answer must be
re-assessed before the next store submission (likely "User ID — not linked to
identity, App Functionality"); that call is a store-submission gate (Bilal).
brewdesk#48 (real accounts) replaces this UUID and owns the final privacy
position.

### Recent searches (bd#223) — on-device only, never sent

`RecentSearchStore` (`Packages/BrewDeskKit/Sources/BrewDeskKit/RecentSearchStore.swift`)
remembers up to 10 recent café selections/searches so the search field can
show them again. It is pure client-side state: a plain `UserDefaults` JSON
blob under `brewdesk.recent-searches` (same CA92.1 UserDefaults reason
already declared for the observation submitter id above), written only by
`RecentSearchStore` itself, read only to render the "Recent" list. Nothing
here ever reaches `VenueAPI` or any other network call — a recent café is
re-flown-to using its already-known coordinate/id, and a recent query is
just typed text re-submitted through the exact same search path already
audited above. Cleared by the shelf's own "Clear" control or by deleting the
app (removes the whole `UserDefaults` domain). Reset to empty (or an explicit
seed) on every UI-test launch (`RecentSearchStore.init`, gated on
`LaunchEnvironment.isUITestRun`) so tests never depend on — or leak into —
whatever a previous run happened to persist.

### Out of band (not URLSession, not interceptable, not ours)

- **MapKit** tiles/geocoding: Apple's GEO XPC service under Apple's privacy
  terms; the app never sees or sends those requests.
- **Directions / Share / "View on Google Maps" / support & legal links**:
  user-initiated hand-offs to Maps, the share sheet, or Safari — out of
  process, after an explicit tap.
- **Image bytes** for Google photo URIs: fetched by SwiftUI `AsyncImage`. The
  app controls only the URL, and the URL is audited (host ≠ engine, no
  coordinate keys, no device-coordinate digits).

## Server side

- The venue engine (`bamware-venue-engine`) has no request logger (no
  `morgan`/`pino`; the only `console.log` is the local-dev listen banner),
  stores no location history, and keeps no user identity. Coordinates are used
  to rank one response and dropped.
- The only retention is **Vercel Runtime Logs**: request rows include
  *Search Params* (Vercel docs, *Runtime Logs → Log details*, updated
  2026-08-03), kept **1 h on Hobby / 1 day on Pro / 30 days with
  Observability Plus**. No log drain is configured (`vercel.json` has no
  logging config). Listing fetch (brewdesk#154 / engine #16) sends the
  map-query centre as `X-BrewDesk-Viewport`, which Vercel request logs do not
  retain; Search Params on that path are filters only (`sort`, `limit`,
  `radius_m`, amenity mins, …). Re-assess if a log drain is added, headers
  start being retained, or any analytics/crash SDK is introduced.
- The engine still accepts query-string `lat`/`lng` for older clients. This
  app no longer sends them. The privacy position in bamware-ai
  `docs/brewdesk-go-live.md` (not in this repo) should cite the header
  channel once a follow-up lands there.

## Tests

| Suite | Target | Runs | Proves |
| --- | --- | --- | --- |
| `PrivacyRequestAuditTests` | `VenueKitTests` | package tests (CI on every PR) | per-flow host + param audit via `RecordingURLProtocol` injected into `VenueAPI(session:)`; listing coords travel only as `X-BrewDesk-Viewport` (never in the query string); denied → anchor only; granted → engine only; photo URLs coordinate-free; wire vocabulary closed |
| `VenuesModelPrivacyTests` | `BrewDeskKitTests` | package tests (CI) | anchor when no location; any granted coordinate (including far from NYC) is the only other value sent |
| `ObservationSubmissionTests` | `VenueKitTests` | package tests (CI) | observation submit reaches only the engine; body is exactly `{submittedBy, answers}` with enum-string values (no free text, no coordinates under any plausible key) |
| `PrivacyClaimTests` | `BrewDeskTests` (host app) | Release app unit tests (CI step "Release app unit tests (privacy audit)") | shipped `PrivacyInfo.xcprivacy` = no tracking / no collected data / UserDefaults CA92.1 only; When-In-Use location only; Release endpoint is HTTPS production with no ATS exception; fallback query = Union Square |

Re-run locally:

```bash
cd Packages/BrewDeskKit
xcodebuild -scheme BrewDeskKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:VenueKitTests/PrivacyRequestAuditTests \
  -only-testing:BrewDeskKitTests/VenuesModelPrivacyTests test

cd ../..
xcodebuild -project BrewDesk.xcodeproj -scheme BrewDesk \
  -configuration Release ENABLE_TESTABILITY=YES \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BrewDeskTests/PrivacyClaimTests test
```

`RecordingURLProtocol` is never registered globally; it only sees sessions it
creates, so it cannot interfere with other suites in the same host.

## Photo source (corrected — brewdesk#156)

`VenueAPI.absolutePhotoURL` and the `VenuePhoto` comments in `VenueAPI.swift`
/ `Models.swift` used to describe a same-origin `/media` proxy. Production
returns Google's `photoUri` verbatim, so that branch is dead and the client
loads photo bytes from `lh3.googleusercontent.com`. The comments now match;
the audit above reflects the real behaviour.
