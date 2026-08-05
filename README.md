# bamware-cafe

NYC work-cafe finder — **tenant #3** on the bamware platform. SwiftUI app +
`BamwareCafeKit` local package, consuming the shared `bamware-ios` monorepo
(BamwareCore/BamwareUI) and the `bamware-venue-engine` backend (2,180 real
NYC cafes, wifi/outlets/laptop-policy claims with provenance).

## Package structure

You already built the hard part. There are two layers:

1. **`bamware-ios`** is a multi-product Swift package repo with Core, UI, and
   Messaging libraries. `BamwareCafeKit` resolves it from GitHub and the app's
   committed `Package.resolved` pins the exact revision.
2. This repo keeps app-private modules in the in-repo `Packages/` folder.

```
bamware-cafe/                        ← this repo
├─ BamwareCafe.xcodeproj             ← thin app target (Xcode 16 synced folders)
├─ BamwareCafe/                      ← app shell ONLY: @main, RootView, DI root
│  └─ Dependency/Container.swift     ← Factory composition root
├─ Packages/
│  └─ BamwareCafeKit/                ← in-repo local package (the real code)
│     ├─ Sources/VenueKit/           ← models + API client (pure, no UI)
│     └─ Sources/BamwareCafeKit/     ← screens, VenuesModel, CafeTheme
│              │ depends on ↓
└──────────────┼─── bamware-ios      ← remote shared package (Core, UI)
               └─── Factory          ← remote DI package
```

Dependency chain: **app → BamwareCafeKit → VenueKit + bamware-ios**. The app
shell never imports bamware-ios directly; `CafeTheme` conforms to
`BamwareUI.Theme`, so shared components (`SmartText`) render the cafe brand
with zero changes to the shared package — that's the white-label proof.

## Prerequisites

- Xcode 16.2+ with an iOS 17+ simulator
- The backend running: `cd bamware-venue-engine && npm install && npm run dev` (localhost:3000)

## Run

1. Start the backend (above).
2. `open BamwareCafe.xcodeproj`
3. If packages don't resolve on first open: File → Packages → Resolve Package Versions.
4. Run on an iPhone simulator — the simulator reaches `http://localhost:3000` directly.

The app flow is onboarding → StoreKit paywall → Bamware Auth → location →
map-first discovery. Debug builds include a development bypass when StoreKit
products are unavailable. The shared `BamwareCafe` Xcode scheme loads
`BamwareCafe/Products.storekit` with monthly and annual sandbox products.

Authentication uses the shared Bamware Auth service with the isolated
`bamware-cafe` tenant. Access and refresh tokens are stored in the iOS Keychain;
an expired access token is refreshed during app launch when possible.

## Develop shared modules

For normal app work and CI, `BamwareCafe.xcodeproj` resolves the remote,
revision-locked `bamware-ios` package. To change the shared modules and the app
together, clone both repositories as siblings and open the development
workspace instead:

```text
~/code/
├── bamware-cafe/
└── bamware-ios/
```

```bash
open BamwareCafeDevelopment.xcworkspace
```

Xcode substitutes the sibling checkout for the remote package with the same
identity. Changes under `../bamware-ios/Sources` then build immediately in the
cafe app, while each repository keeps its own history and release lifecycle.
Do not replace the manifest dependency with a machine-specific `.package(path:)`.

Command-line build:

```bash
xcodebuild -project BamwareCafe.xcodeproj -scheme BamwareCafe \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Local shared-module build:

```bash
xcodebuild -workspace BamwareCafeDevelopment.xcworkspace -scheme BamwareCafe \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Package tests must use the generated package scheme because plain `swift test`
targets macOS by default while this package graph is iOS-only:

```bash
cd Packages/BamwareCafeKit
xcodebuild -scheme BamwareCafeKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Test the shared engine independently after changing it:

```bash
cd ../bamware-ios
swift test
```

What you'll see: a map-first view of 100 real cafes near your location (Union
Square fallback), readable Work Fit markers, search, laptop/Wi-Fi/outlet
filters, synchronized venue cards, and details with claim provenance. Speed
observations are disabled against the localhost engine so loopback measurements
cannot contaminate trusted data.

## Make it a git repo + push to GitHub

```bash
cd ~/code/bamware-cafe
git init -b main
git add -A
git commit -m "bamware-cafe: SwiftUI app + BamwareCafeKit on bamware-ios + venue-engine"
gh repo create mrbam88/bamware-cafe --private --source=. --remote=origin --push
```

## Troubleshooting

- **"Missing package product BamwareCafeKit"** → File → Packages → Resolve. If
  it persists, remove and re-add the local package (Project → Package
  Dependencies → + → Add Local… → `Packages/BamwareCafeKit`).
- **bamware-ios fails to resolve** → reset package caches, then resolve package
  versions again. The app does not require a sibling checkout.
- **HTTP requests fail in Release** → localhost HTTP is intentionally allowed
  only in Debug. Configure a real HTTPS backend before distributing the app.

## Before Release

1. Configure a real HTTPS venue-engine endpoint for Release builds.
2. Decide whether venue observations are global or tenant-scoped and enforce
   that boundary in the backend and API client.
3. Replace the provisional speed measurement with an uncacheable, known-size
   backend payload plus server-side validation and idempotency.
4. Initialize this directory as a repository and add app/package CI.
- **This .xcodeproj was hand-authored** (adapted from BamwareDemoApp's, no Xcode
  involved). If Xcode complains about anything structural, say the word and
  I'll fix the pbxproj.

## Interview talking points baked in

Modular monorepo (app shell vs. feature package vs. pure networking kit) ·
DI at the composition root only, packages stay framework-agnostic ·
`@MainActor @Observable` view model, Swift 6-clean `Sendable` models ·
cross-package theming via protocol conformance (tenant #3) ·
trust UI: every attribute renders source + confidence + freshness ·
latest-request-wins filtering prevents stale results from replacing current data.
