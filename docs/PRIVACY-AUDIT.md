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
| Map / Nearby list | `GET /v1/venues?sort&limit&radius_m&lat&lng[&filters]` | engine | `lat`, `lng` — the **map-query centre** (see below) |
| Stat strip | `GET /v1/health` | engine | none |
| Detail | `GET /v1/venues/{id}` | engine | none |
| Photo strip / viewer (list) | `GET /v1/venues/{id}/photos` | engine | none |
| Photo strip / viewer (bytes) | `GET <photoUri>` via `AsyncImage` | `lh3.googleusercontent.com` | none — opaque Google photo URI, no place_id, no coordinates |
| Neighborhood chips | `GET /v1/neighborhoods` | engine | none |
| Import from Takeout | `GET /v1/venues?sort&limit=200&radius_m` | engine | none |
| *(not reachable in v1 UI)* speed test | `POST /v1/observations` `{venueId,kind,mbpsDown}`; probe `GET /v1/venues?limit&_speed_test_nonce` | engine | none |

The complete query vocabulary `VenueQuery` can emit is
`sort limit radius_m lat lng wifi_min outlets_min minSeating venueType laptops
neighborhood q`; only `lat`/`lng` can carry a location. A test fails if that
set changes.

### What `lat`/`lng` contain

| Location state | Value sent | Why |
| --- | --- | --- |
| Not determined / **denied** / "Use Union Square instead" | `40.7359, -73.9911` — Union Square, the hardcoded coverage anchor (`VenuesModel.coverageCenter*`) | `LocationService.location` stays `nil`; the model never receives a device coordinate |
| Granted, **outside NYC coverage** (e.g. App Review in California) | the anchor again | `VenuesModel.updateCenterIfNeeded` rejects coordinates > 50 km from the anchor; the device coordinate is discarded, "Browse NYC" re-queries the anchor |
| Granted, inside coverage | the device coordinate, full precision | needed to rank by proximity; sent to the engine only, used transiently |

So a user who denies location — and every reviewer outside NYC — never has a
device coordinate leave the phone. This is asserted, not assumed
(`VenuesModelPrivacyTests`, `PrivacyClaimTests.fallbackQueryTargetsUnionSquareNotTheDevice`).

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
  logging config). Transient platform retention of a map-query centre is
  consistent with Apple's real-time-processing carve-out; re-assess if the
  plan changes, a log drain is added, or any analytics/crash SDK is introduced.
- Follow-up (tracked separately): move the viewport coordinate out of the
  query string (request header or `POST` body), which Vercel request logs do
  not retain, once #27's `VenueAPI` changes have merged.

## Tests

| Suite | Target | Runs | Proves |
| --- | --- | --- | --- |
| `PrivacyRequestAuditTests` | `VenueKitTests` | package tests (CI on every PR) | per-flow host + param audit via `RecordingURLProtocol` injected into `VenueAPI(session:)`; denied → anchor only; granted → engine only; photo URLs coordinate-free; wire vocabulary closed |
| `VenuesModelPrivacyTests` | `BrewDeskKitTests` | package tests (CI) | anchor when no location; out-of-coverage device coordinate never sent; in-coverage coordinate is the only other value |
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

## Known stale comments (not changed here — #27 owns `VenueAPI.swift`)

`VenueAPI.absolutePhotoURL` and the "Places proxy" comments in `VenueAPI.swift`
/ `Models.swift` describe a same-origin `/media` proxy; production returns
Google's `photoUri` verbatim, so that branch is dead and the client loads
photo bytes from `lh3.googleusercontent.com`. The audit above reflects the
real behaviour.
