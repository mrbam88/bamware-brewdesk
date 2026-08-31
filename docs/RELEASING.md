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

### Release-branch flow (REQUIRED — decided by Bilal 2026-08-30)

Command-line overrides (`STORE_SURFACE_GATED=YES` on the archive command)
are FORBIDDEN for store archives: they leave no trace in git, so the
submitted binary's state is invisible to history. Every store archive must
be reproducible from a tagged commit:

1. Cut a release branch from the exact main commit being shipped:
   `git checkout -b release/1.0.3 main`
2. Commit the flip ON THE BRANCH — set `STORE_SURFACE_GATED = YES` in
   `BrewDesk.xcodeproj/project.pbxproj` as a normal one-line commit
   ("release: gate store surface for 1.0.3 submission").
3. Archive from the branch with NO build-setting overrides:
   `xcodebuild archive -project BrewDesk.xcodeproj -scheme BrewDesk -destination 'generic/platform=iOS' -allowProvisioningUpdates`
4. Verify before upload: the exported app's Info.plist contains
   `BDStoreSurfaceGated = YES`, and `StoreSurfaceGateUITests` passes on the
   branch.
5. After Apple assigns the build number, tag the archived commit:
   `git tag store/1.0.3-buildN && git push --tags`
6. Push the branch. It is retired after approval — never merged back, never
   long-lived. `main` NEVER carries the flip; the next submission cuts a
   fresh branch.

Result: `git diff main..store/1.0.3-buildN` shows exactly what the reviewer
received — one commit, one setting. A long-lived "store" branch is equally
forbidden: permanent divergence is how real feature drift starts.
