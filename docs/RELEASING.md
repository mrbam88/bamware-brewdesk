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

## Store-submission surface gate — removed (bamware-brewdesk#174, C9)

The `STORE_SURFACE_GATED` build setting / `BDStoreSurfaceGated` Info.plist
key / `StoreSurface.isGated` mechanism described in earlier revisions of
this doc is gone. brewdesk#67's accountless-submission strategy is retired:
BrewDesk now ships accounts (Apple, Google, email via the shared
`BamwareAccounts`/`BamwareAccountUI` packages), report/block, and the
observation entry card in every build, store submission included — there is
no longer a build that hides them. The App Privacy label changes
accordingly; see `submission/1.1/metadata/privacy-label.md` for the answers
Bilal enters in App Store Connect (Human-only — no App Store action was
taken by this ticket).

Store archives now follow the same `xcodebuild archive` command as before,
with no `STORE_SURFACE_GATED` override and no separate release-branch flip —
a store archive is just a normal signed `Release` archive from `main` (still
cut a release branch per the usual TestFlight/build-number discipline; there
is simply no longer a build-setting commit to make on it).

## Human-only handoff for accounts (bamware-brewdesk#174, C9)

Before the next TestFlight/store build ships real sign-in:

- **Sign in with Apple**: add the "Sign in with Apple" capability to the
  `io.bamware.brewdesk` App ID in the Apple Developer portal (Certificates,
  Identifiers & Profiles). `BrewDesk/BrewDesk.entitlements` and the Xcode
  project's `CODE_SIGN_ENTITLEMENTS` setting are already wired — signing/
  provisioning/team were not touched by this ticket (hard stop) and
  "Automatically manage signing" should pick up the capability on next
  build once the App ID has it, but that account-portal step is Human-only.
- **Google sign-in**: provision an iOS OAuth client id in Google Cloud for
  this app, then fill in `GIDClientID` and the `CFBundleURLTypes` reversed-
  client-id placeholder in both `BrewDesk-Debug-Info.plist` and
  `BrewDesk-Store-Info.plist` (each has a `TODO(Bilal)` comment marking the
  exact keys). Until then the Google button stays hidden —
  `AccountModel.availableProviders` omits it when no client id is
  configured, so this is safe to ship as-is.
- **Privacy label**: enter the answers in `submission/1.1/metadata/
  privacy-label.md` into App Store Connect's App Privacy questionnaire.
