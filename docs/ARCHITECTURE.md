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
└── BamwareUI

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

## Configuration

`VenueAPI.defaultBaseURL` is selected at compile time:

- Debug: `http://localhost:3000`
- Release: deployed HTTPS Venue Engine

The Debug plist permits local HTTP only for development. Production does not
accept a runtime environment switch that could leak into a store archive.

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
