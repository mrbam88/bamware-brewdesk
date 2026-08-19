# Testing BrewDesk

Tests are evidence with different scopes. Run the smallest relevant test while
developing, then the complete release matrix before TestFlight.

## Package tests

```bash
cd Packages/BrewDeskKit
xcodebuild -scheme BrewDeskKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

These prove model decoding, typed filters, latest-request-wins behavior, and
Saved persistence/hydration. They do not prove app composition or the live API.

## App and UI tests

```bash
xcodebuild -project BrewDesk.xcodeproj -scheme BrewDesk \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

The app suite covers flow persistence and Release configuration. UI tests cover
navigation, English/Spanish launch, accessibility-size layouts, accessibility
audit, launch configurations, and deterministic screenshot capture.

Use Release for the final run so tests exercise the production endpoint:

```bash
xcodebuild -project BrewDesk.xcodeproj -scheme BrewDesk \
  -configuration Release ENABLE_TESTABILITY=YES \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

## Shared-package workspace

```bash
xcodebuild -workspace BrewDeskDevelopment.xcworkspace -scheme BrewDesk \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

This proves BrewDesk still compiles while substituting the sibling
`bamware-ios` checkout.

## iPad compatibility

Although BrewDesk is iPhone-only, Apple may review it on iPad:

```bash
xcodebuild -project BrewDesk.xcodeproj -scheme BrewDesk \
  -configuration Release ENABLE_TESTABILITY=YES \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -only-testing:BrewDeskUITests/BrewDeskUITests/testDiscoveryTabsExist test
```

## Unsigned archive

An unsigned archive proves generic-device Release compilation and bundle
assembly without invoking credentials:

```bash
xcodebuild -project BrewDesk.xcodeproj -scheme BrewDesk \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO archive
```

It does not prove distribution signing or upload.

## Identity and asset checks

```bash
./.github/scripts/check-identity.sh
sips -g pixelWidth -g pixelHeight -g hasAlpha fastlane/screenshots/en-US/*.png
git diff --check
```

## Physical-device matrix

Test the exact TestFlight build:

- Fresh install
- Location allowed
- Location denied
- Location previously granted
- Union Square fallback
- Search and each filter
- Save/unsave persistence
- Directions and Share
- English and Spanish
- Large Dynamic Type and VoiceOver
- Claim source/confidence/date legibility

## Release definition of done

1. Package tests pass.
2. Full Release app/UI tests pass.
3. Production API responds through the Release client.
4. Workspace Release build passes.
5. iPad compatibility smoke passes.
6. Unsigned archive passes.
7. Identity and screenshot checks pass.
8. Signed upload reaches App Store Connect.
9. Apple processing reports `VALID`.
10. The exact build installs and passes the physical-device matrix.
