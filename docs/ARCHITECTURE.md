# BrewDesk architecture

This document explains why the code is shaped this way and where new work
belongs. The intended reader is future Bilal or a developer joining the app
without its chat history.

## Product architecture

BrewDesk is intentionally data driven. The Venue Engine owns venue facts,
provenance, confidence, filtering, and ranking. The iOS app owns native
interaction, accessibility, presentation, and local preferences.

The API returns semantic facts. It does not return layout instructions. This
keeps scoring deployable without an App Store release while preserving a
coherent native product.

## Dependency boundaries

```text
BrewDesk app target
├── lifecycle and flow
├── Core Location adapter
├── configuration and legal URLs
├── BrewDeskKit
└── VenueKit protocols/concrete API

BrewDeskKit product
├── SwiftUI feature screens
├── VenuesModel
├── SavedVenuesStore
├── VenueKit
├── BamwareCore
├── BamwareUI
├── BamwareAccounts / BamwareAccountsGoogle
└── BamwareAccountUI

VenueKit product
├── immutable Sendable domain values
├── typed VenueQuery
├── capability protocols
└── URLSession implementation
```

Rules:

- `VenueKit` never imports SwiftUI or a consumer app.
- Feature UI never resolves global dependencies.
- The app target constructs concrete dependencies and passes capabilities in.
- Shared `bamware-ios` products never import BrewDesk.
- Backend response changes require paired client changes and live verification.

## Capability protocols

The API is split by what a consumer needs:

- `VenueListing`: search/filter listing queries
- `VenueDetailServing`: refresh a venue by identifier
- `VenueMeasuring`: deferred measurement/submission capability

This is interface segregation, not a generic repository framework. Discovery
tests should not implement speed-test methods, and Saved should not depend on
the entire client.

## Score display contract (brewdesk#213)

The engine sends `workScore` (always a number — a flat neutral placeholder
for a venue with no real evidence, never `nil`) and an additive
`scoreDisplay` alongside it: a number for a rated café (equal to
`workScore`), JSON `null` for a genuinely unrated one, or the key absent
entirely on an older server / a metro outside the rollout.

`decodeIfPresent` cannot tell "key absent" from "key present with `null`"
apart — both collapse to `nil` — so `Venue` is NOT a synthesized `Codable`
any more. Its manual `init(from:)`/`encode(to:)` call `container.contains(
.scoreDisplay)` before decoding, producing `ScoreDisplay`:

- `.rated(Int)` — the wire number.
- `.notRated` — an explicit server `null`. `displayScore` is `nil`, ALWAYS,
  even if the client's own `isObserved` heuristic disagrees. Never falls
  back to `workScore`.
- `.notProvided` — the key was absent. `displayScore` falls back to
  `isObserved ? workScore : nil` — the pre-#213 behavior, unchanged, so the
  app keeps working against a server that hasn't shipped the field.

Every score-rendering surface (map marker split, shelf tile, detail badge,
list rows, share text, VoiceOver labels, ordering) reads `Venue.displayScore`
/ `Venue.isRated`, never `workScore`/`isObserved` directly, so the server's
explicit opinion always wins when it has one. Encoding round-trips all three
states — `.notProvided` omits the key rather than fabricating a `null`.

## Discovery state flow

`DiscoveryRootView` owns the shared `VenuesModel`. Explore and Nearby receive
the same observable instance, which is why filters and results stay in sync.

```text
gesture / search / location
  -> mutate VenuesModel input
  -> VenueLoadRequest(query, revision) changes
  -> SwiftUI .task(id:) cancels previous task
  -> VenueListing.fetchVenues(query)
  -> generation guard rejects stale completion
  -> phase + venues update
  -> observing views redraw
```

Search text is separate from submitted search. Typing does not issue a request;
submission updates query identity. Retry increments a revision without
polluting the API model.

## Saved state

`SavedVenuesStore` owns an ordered list of venue IDs and persists it through a
small `SavedVenuePersisting` boundary. IDs are stored instead of complete venue
snapshots because Work Fit and provenance can change server-side.

`SavedVenuesModel` hydrates those IDs through `VenueDetailServing`, preserving
saved order. The store is shared by map, list, details, and Saved so there is
one source of truth.

## Concurrency

- UI state is `@MainActor` and uses `@Observable`.
- Domain/API values are immutable and `Sendable`.
- `URLSession.data(for:)` suspends without blocking the main thread.
- View-owned `.task(id:)` work is cancelled with view/query identity.
- `LocationService` consumes `CLLocationUpdate.liveUpdates()` as an
  `AsyncSequence` and owns its cancellable task.
- A generation counter protects against dependencies that ignore cancellation.
- There are no detached tasks or unchecked Sendable escapes.

Actors are for shared mutable state with independent lifetime. Main-actor UI
models do not need to become actors merely because they call async functions.

## Shared bamware-ios packages

`Packages/BrewDeskKit/Package.swift` pins `bamware-ios` to an exact
revision (`BamwareAccounts`, `BamwareAccountsGoogle`, `BamwareAccountUI` as
of bamware-brewdesk#174/C9). `BrewDeskDevelopment.xcworkspace` substitutes
the pin for the sibling `../bamware-ios` checkout for local development
against unreleased shared-package changes — **that substitution needs the
sibling checkout at or ahead of the pinned revision
(`ac444619a96e5e018b33f6c2acf7d6dac0839415`) to build**; an older sibling
checkout is missing the account packages entirely. This could not be
verified when bamware-brewdesk#174 landed because the sibling checkout in
that environment was stale and behind the pin — say so rather than silently
skip it. `xcodebuild -project BrewDesk.xcodeproj` (the remote pin) is
unaffected either way.

## Community writes and the user JWT (bamware-brewdesk#202)

venue-engine PR #145 adds `communityAuth` on the four community write routes
(`POST /v1/observations`, `POST /v1/venues/:id/observations`,
`POST /v1/venues/:id/photos`, `POST /v1/reports`). It is a pass-through today
(production runs `PRIVATE_STORAGE=json`); once the engine flips to
`PRIVATE_STORAGE=postgres`, those routes require the BrewDesk user JWT and set
`submittedBy` from it.

- `VenueAPI` takes two constructor-injected closures — `tokenProvider` and
  `tokenRefresher` (`@Sendable () async -> String?`), same shape
  `ServerSavedVenuePersistence.tokenProvider` already uses for saved-spots
  sync. Both default to `{ nil }`, so any call site that doesn't pass them
  (most GET-only `VenueAPI()` instances) behaves exactly as before this
  ticket. `ObservationServiceResolver.resolve()` wires the production pair:
  `BrewDeskAccountTenant.freshAccessToken` / `.refreshAccessTokenAfterUnauthorized`.
- `submitSpeedTest` (`POST /v1/observations`) and `submitObservation`
  (`POST /v1/venues/:id/observations`) both route through one private seam,
  `VenueAPI.postAuthenticated`: attach `Authorization: Bearer <token>` when
  signed in; on a signed-in 401, force one refresh
  (`SessionRefresher.refreshAfterUnauthorized()`, which bypasses the
  proactive-expiry check `freshAccessToken`'s `validAccessToken()` already
  did) and retry once; if that also 401s, or refresh itself fails, throw
  `VenueAPIError.authenticationRequired` instead of the generic `.http(401)`.
  A signed-out request (no token to begin with) is unchanged — its 401, if
  any, still surfaces as plain `.http(statusCode: 401)`.
- `ObservationFormModel` maps `.authenticationRequired` to a new
  `Phase.signInRequired` (distinct from the generic `.failed(message:)`
  banner) rather than losing the draft — every answer is a plain stored
  property, independent of `phase`, so nothing is cleared. `submit()` can be
  called again once the user signs in (`ObservationFormScreen` presents
  `SignInScreen` on that phase, copy "Sign in to submit", and retries
  automatically on `AccountModel.sessions.isSignedIn` flipping true).
- `POST /v1/venues/:id/photos` (`VenueIntakeAPI.linkUploadedPhoto`, the
  Debug-only community-capture rail, bd#71) already required sign-in and
  already sent `Authorization: Bearer <token>` before this ticket — its 401
  handling (no auto-refresh; "sign in again" is the documented recovery) is
  unchanged, out of #202's tested scope since capture never ships in a store
  build.
- `POST /v1/reports` has no wire client yet — `ReportContract.swift`'s
  `ReportSpool` still only spools reports locally, pending a future
  venue-engine ticket. Nothing to add a bearer token to until that lands.

## Configuration

`VenueAPI.defaultBaseURL` is selected at compile time:

- Debug: `http://localhost:3000`
- Release: deployed HTTPS Venue Engine

The Debug plist permits local HTTP only for development. Production does not
accept a runtime environment switch that could leak into a store archive.

`VenueAPI` uses a 15-second request timeout so a stalled engine becomes an
explicit error state with Retry instead of a long spinner.

`BrewDeskAccountTenant.defaultAuthBaseURL` (`AccountComposition.swift`)
mirrors the same Debug/Release split for `bamware-auth-service`: Debug talks
to a local `pnpm dev` instance, Release to the deployed dev-stage Lambda.
`BamwareAccounts` itself holds no base URL or tenant constant — every value
flows in through the app-owned `AccountTenantConfig` this file builds.

UI tests may pass `-UITestScenario <name>` / `-UITestLocationDenied`
(`UITestScenario` in the app target) to swap in `ScenarioVenueService`
fixtures. The seam compiles in Release because the release gate runs UI tests
in Release; it is a single launch-argument lookup with no UI entry point and
no network, same precedent as `-UITestSkipGates`.

## Localization and accessibility

User-facing copy lives in Xcode string catalogs with English and Spanish.
Backend enum values remain stable wire values and are mapped to localized
display labels in the UI.

The UI uses semantic fonts, accessibility-size layouts, non-color state, and
minimum interaction targets. Liquid Glass is progressive enhancement on iOS
26; iOS 17 uses system materials through the same view modifier.

## Adding a feature

1. Define the user job and decide whether intelligence belongs in the API.
2. Verify the current backend schema before changing client models.
3. Add the narrowest capability protocol needed by the consumer.
4. Keep observable state in the feature package and concrete composition in the
   app target.
5. Add English and Spanish strings with accessibility labels at implementation
   time.
6. Test pure transformations, state transitions, UI flow, and the live Release
   integration at the appropriate layers.
7. Re-run screenshots and release gates if the visible flow changed.

## Intentional non-goals

- No generic repository hierarchy
- No coordinator framework for three tabs
- No server-driven UI
- No account abstraction before cloud saves exist
- No Combine dependency where Observation or AsyncSequence is simpler
- No client types trusted without checking the backend contract
