# Releasing BrewDesk

BrewDesk uses native fastlane CI for TestFlight:

```text
workflow dispatch
  -> macOS 26 / Xcode 26.5
  -> import the existing Apple Distribution certificate
  -> sigh creates or downloads the App Store provisioning profile
  -> gym archives and exports BrewDesk
  -> pilot uploads the next build number to TestFlight
```

Unlike Baat, BrewDesk is a pure Swift app and cannot use EAS Build. Baat's
GitHub workflow delegated signing and submission to credentials stored by EAS;
BrewDesk stores the equivalent capabilities as encrypted GitHub Actions
secrets and runs fastlane on a hosted Mac.

The first TestFlight build used a second, proven path: Xcode authenticated with
a Team App Store Connect API key, created a cloud-managed distribution
signature during export, uploaded directly, and waited for processing. This
path does not produce an exportable local private key for GitHub CI.

## Credential vocabulary

- `.p8`: App Store Connect API private key
- Key ID: short identifier for the API key
- Issuer ID: team UUID used with the key
- `.cer`: public signing certificate only
- `.p12`: certificate plus exportable private key
- `.mobileprovision`: profile tied to a specific bundle identifier

A Baat provisioning profile cannot sign BrewDesk. A `.cer` without its matching
private key cannot sign any archive. Never commit or print credential values.

## One-time secret setup

Add these encrypted Actions secrets to the repository's protected
`production` environment, restricted to the default branch:

| Secret | Source |
|---|---|
| `ASC_KEY_ID` | Existing App Store Connect API key ID |
| `ASC_ISSUER_ID` | Existing App Store Connect issuer ID |
| `ASC_KEY_P8_B64` | Base64-encoded contents of the existing `.p8` key |
| `IOS_DISTRIBUTION_CERT_P12_B64` | Base64-encoded existing Apple Distribution certificate and private key |
| `IOS_DISTRIBUTION_CERT_PASSWORD` | Password used when the `.p12` was exported |

The distribution certificate can be reused across apps owned by team
`BZRTC4A75L`. The provisioning profile is app-specific; fastlane creates or
downloads the `io.bamware.brewdesk` profile through App Store Connect.

Never commit credential values. Add them in GitHub Settings -> Environments ->
production -> Environment secrets, or enter them interactively with
`gh secret set --env production`.

## Ship

Dispatch **TestFlight** from the GitHub Actions page. The lane reads the current
marketing version, finds the latest TestFlight build for that version, assigns
the next build number in the runner checkout, uploads an internal build, and
waits until Apple finishes processing it. The project file in git is not
modified by the build-number increment.

CLI dispatch:

```bash
gh workflow run testflight.yml --repo mrbam88/bamware-brewdesk
```

Monitor it with:

```bash
gh run watch --repo mrbam88/bamware-brewdesk
```

## Store-submission surface gate (brewdesk#67)

The App Store submission binary must be an accountless app matching the
"Data Not Collected" privacy label, so the store archive hides the Account
entry, photo report/block actions, and the observation entry card. This is a
build *configuration* flag, not `#if DEBUG` — TestFlight and the store both
build Release.

- Mechanism: `STORE_SURFACE_GATED` build setting (default `NO` in every
  checked-in configuration) → `BDStoreSurfaceGated` key in the merged
  Info.plist (`BrewDesk-Store-Info.plist`) → read at runtime by
  `StoreSurface.isGated` in BrewDeskKit.
- TestFlight rail: unchanged. Plain `Release` keeps every feature ON.
- Store submission archive — the one-line flip is a build-setting override
  on the archive command:

```bash
xcodebuild archive -project BrewDesk.xcodeproj -scheme BrewDesk \
  -destination 'generic/platform=iOS' STORE_SURFACE_GATED=YES
```

(For a fastlane lane, the equivalent is `xcargs: "STORE_SURFACE_GATED=YES"`
on `build_app`.) Verify before upload: the exported app's Info.plist must
contain `BDStoreSurfaceGated = YES`, and `StoreSurfaceGateUITests` proves the
gated surface renders none of the gated UI. The flag flips back in the first
post-approval update by archiving without the override.
