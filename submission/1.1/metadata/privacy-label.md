# App Privacy label — 1.1 (bamware-brewdesk#174, C9)

For Bilal to enter in App Store Connect → App Privacy. Human-only — no App
Store Connect action was taken by this ticket; this is the answer set the
new account/UGC surfaces require, replacing the "Data Not Collected" label
the retired `StoreSurface` gate was built to preserve (brewdesk#67).

Tracking: still **No** — `PrivacyInfo.xcprivacy`'s `NSPrivacyTracking` stays
`false`. Nothing here is used to track the user across other companies'
apps/sites, and there are still no ad/analytics/attribution SDKs in the app.

## Data types to declare

| Data type | Collected? | Linked to identity? | Used for tracking? | Purpose |
|---|---|---|---|---|
| **Email Address** | Yes | Yes (account holder) | No | App Functionality — account creation/sign-in (`bamware-auth-service`) |
| **Name** | Yes | Yes (account holder) | No | App Functionality — displayed back to the user on the Account screen; attributed to community photo/observation submissions made while signed in |
| **User ID** | Yes | Yes | No | App Functionality — the auth service's internal user id (`AuthUser.userId`), never shown to the user, used only to key the account and its content server-side |
| **Photos** | Yes | Optional (see note) | No | App Functionality — community venue photos, submitted with a caption; visible to all users of the app |
| **Other User Content** | Yes | Optional (see note) | No | App Functionality — structured "rate this visit" observations (Wi-Fi/seating/outlets/noise/laptop-policy answers); contributes to a venue's aggregate score, not shown as authored content |
| **Device ID** | Yes | No (until account submissions ship) | No | App Functionality — a random, on-device-generated per-install UUID (`ObservationSubmitterIdentity`) sent with anonymous photo/observation submissions so a submission can be attributed to "this install" for report/block purposes without requiring an account. Not the device's real identifier (IDFV/IDFA) — a UUID this app generates and stores in `UserDefaults`. |
| **Precise Location** | Yes (unchanged from the pre-C9 label) | No | No | App Functionality — nearby-venue search; requires the user's explicit in-app grant, always optional (Union Square fallback) |

## Notes for the "linked to identity" column

- **Photos / Other User Content**: today every submission is anonymous
  (the per-install UUID above), regardless of whether the submitter happens
  to be signed in — account-attributed submissions are explicitly out of
  this ticket's scope (`ObservationFormModel.swift`'s "UPGRADE POINT"
  comment: real accounts replacing the UUID is future work, not shipped
  here). Answer **"Data used, but not linked to your identity"** for both
  until that upgrade ships; revisit this file when it does.
- **Password**: not a data type Apple's questionnaire asks about directly
  for App Privacy (it's collected by the account form but is not one of the
  listed categories) — no entry needed.
- **Account deletion**: in-app, ordered (content → auth record → local
  session), reachable from the You tab. Confirms the "Data deletion" answer
  Apple's questionnaire asks for account-holding apps.

## Not collected

Everything else stays "Data Not Collected": no analytics, no advertising
identifiers, no crash reporting, no purchase history, no contacts, no
browsing/search history sent to a third party, no financial info, no health
data.

## Device id / token — once push ships (out of scope here)

The push platform (`BamwarePush`, D package in
`bamware-ai/docs/bamware-account-platform.md`) is **not wired into BrewDesk
by this ticket** (explicitly out of scope, same doc's "Out of scope"
section: "push"). When it ships, add a **Device ID** row (or extend the one
above) covering the APNs push token, and a **purpose** of "App
Functionality" (saved-spot alerts) — `PushDeviceRegistering`'s `POST
/devices` body is `{deviceId, token, platform, preferences?}`. Flagging here
so it isn't missed when D14 lands.
