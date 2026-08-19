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
