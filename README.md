# BrewDesk

Native SwiftUI guide to work-friendly New York City cafés. BrewDesk ranks
venues by Work Fit and shows the source, confidence, and observation date
behind Wi-Fi, outlet, laptop-policy, and noise claims.

Canonical identity: app, target, module, and scheme `BrewDesk`; bundle
identifier `io.bamware.brewdesk`; repository `mrbam88/bamware-brewdesk`.

## Status

- Version `1.0 (1)` is processed and working through internal TestFlight.
- The app has not been submitted for App Review.
- The primary review risk is Guidelines 4.2/4.3. Evidence and provenance must
  remain central in the binary, screenshots, and review notes.
- Durable release state lives in
  [`bamware-ai/docs/brewdesk-go-live.md`](https://github.com/mrbam88/bamware-ai/blob/main/docs/brewdesk-go-live.md).

## V1 product

Included:

- Free, accountless discovery
- Optional location with a Union Square fallback
- Map, list, search, and work-specific filters
- Local saved cafés
- Work Fit details with claim-level provenance
- Apple Maps directions and native sharing
- English and Spanish localization

Explicitly out of scope:

- Accounts and cloud saves
- StoreKit and subscriptions
- Public reviews, reports, or conversations
- User-triggered speed submissions
- Analytics, advertising, or tracking

## Quick start

Requirements:

- Xcode 26.x with Swift 6.2+
- iOS 17+ simulator
- Sibling checkouts under `~/code` for local shared-package development

Debug uses the Venue Engine at `http://localhost:3000`. Start it first:

```bash
cd ../bamware-venue-engine
npm install
npm run dev
```

Then open and run the app:

```bash
open BrewDesk.xcodeproj
```

Select the `BrewDesk` scheme and an iPhone simulator. Release builds use the
deployed HTTPS Venue Engine automatically.

## Repository map

```text
bamware-brewdesk/
├── BrewDesk/                         thin app target
│   ├── BrewDeskApp.swift             lifecycle
│   ├── RootView.swift                composition + app flow
│   ├── Flow/                         onboarding, location, tabs
│   └── Location/                     Core Location adapter
├── Packages/BrewDeskKit/
│   ├── Sources/BrewDeskKit/          feature UI + observable state
│   ├── Sources/VenueKit/             Sendable models + async API client
│   └── Tests/                        package tests
├── BrewDeskTests/                    app-shell tests
├── BrewDeskUITests/                  UI, localization, a11y, screenshots
├── fastlane/                         listing assets + release lane
└── docs/                             architecture, learning, tests, release
```

Dependency direction:

```text
BrewDesk app
  -> BrewDeskKit
       -> VenueKit
       -> BamwareCore + BamwareUI (pinned bamware-ios revision)
  -> VenueKit protocols at the composition root
```

The app target owns routing and platform permissions. `BrewDeskKit` owns
feature UI and state. `VenueKit` has no UI dependency.

## How data moves

1. `RootView` creates the concrete `VenueAPI` capabilities.
2. `DiscoveryRootView` owns one `VenuesModel` and one `SavedVenuesStore`.
3. Location, filters, submitted search, or retry create a typed `VenueQuery`.
4. `.task(id:)` cancels work owned by the previous query.
5. `VenuesModel` awaits `VenueListing.fetchVenues` and publishes its phase.
6. Swift Observation invalidates only views that read the changed state.
7. A generation check prevents stale responses from winning even if an API
   implementation ignores cancellation.

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the complete walkthrough.

## Build and test

App tests:

```bash
xcodebuild -project BrewDesk.xcodeproj -scheme BrewDesk \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

Feature/domain package tests:

```bash
cd Packages/BrewDeskKit
xcodebuild -scheme BrewDeskKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Compile against the local sibling `bamware-ios` checkout:

```bash
xcodebuild -workspace BrewDeskDevelopment.xcworkspace -scheme BrewDesk \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

See [docs/TESTING.md](docs/TESTING.md) for what each gate proves.

## Developing shared modules

`BrewDesk.xcodeproj` resolves the revision-pinned remote `bamware-ios` package.
`BrewDeskDevelopment.xcworkspace` includes the sibling checkout and lets Xcode
substitute it immediately.

Never replace the package manifest with a machine-specific `.package(path:)`.
The committed remote revision is what makes standalone and CI builds
reproducible.

## Documentation

- [Architecture](docs/ARCHITECTURE.md): boundaries, state, concurrency, API flow
- [iOS engineering notes](docs/IOS-ENGINEERING-NOTES.md): SwiftUI, Observation,
  Combine, concurrency, DI, and testing as a study guide
- [Testing](docs/TESTING.md): commands and proof matrix
- [Releasing](docs/RELEASING.md): signing, TestFlight, and CI
- [4.3 preflight](fastlane/metadata/4.3-preflight.md): App Review positioning

## Troubleshooting

- **Missing package product:** File -> Packages -> Resolve Package Versions.
- **Debug API fails:** confirm Venue Engine is running on port 3000.
- **Release API fails:** verify `VenueAPI.defaultBaseURL` and the deployed health
  endpoint; Release intentionally cannot use localhost HTTP.
- **Location is empty in Simulator:** Simulator -> Features -> Location, or use
  the Union Square fallback.
- **A UI test skips onboarding:** launch arguments override persisted
  UserDefaults; see `AppStoreScreenshotTests.swift`.
