# Reviewer simulation

`BrewDeskUITests/ReviewerSimulationTests` replays App Review's first ten
minutes as one scripted Release run. It exists so anything a reviewer would
trip over is caught before submission, with screenshots as evidence rather
than a green checkmark. The steps mirror `fastlane/review_information/notes.txt`
and `fastlane/metadata/4.3-preflight.md`.

## Steps and what each one proves

| # | Step | Visible assertion | Screenshot |
|---|---|---|---|
| 1 | Fresh install → onboarding | "Continue" ×2, "Every score shows its work.", "Find my work cafe" | `01`, `02` |
| 2 | Decline location ("Use Union Square instead") | "100 work cafés" + "Gregorys Coffee" on the map | `03`, `04` |
| 3 | Browse: Nearby list, stat strip, Filters → Laptop-friendly only, search "Housing Works" | venue rows; `dataset-stat-strip`; "1 work café" | `05`–`08` |
| 4 | Detail: Housing Works Bookstore Cafe | nav "Details", "Workability", Directions / Save / Share | `09` |
| 5 | Methodology from the Nearby toolbar | nav "How Work Fit works" | `10` |
| 6 | Grant location while simulated at Cupertino | `coverage-banner` ("You're outside NYC — showing our NYC coverage.") **and** "100 work cafés" — the map must not empty (brewdesk#1) | `11` |
| 7 | Offline mid-browse → relaunch | **Pending**: needs brewdesk#27's Release-safe seam (`-UITestScenario offline`, ids `map-state-error` / `map-retry`). Intentionally absent, not silently passing. | — |
| 8 | Relaunch with no overrides | tab bar "Explore" appears, no onboarding replay, dataset reloads | `12` |

Location is simulated with `XCUIDevice.shared.location`; the system permission
alert is answered through SpringBoard (with an interruption monitor as backup).
"Airplane mode mid-browse" is approximated as relaunch-into-offline: the
simulator's network cannot be toggled from XCUITest.

## Run locally

```bash
# iPhone
xcodebuild -project BrewDesk.xcodeproj -scheme BrewDesk \
  -configuration Release ENABLE_TESTABILITY=YES \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:BrewDeskUITests/ReviewerSimulationTests \
  -resultBundlePath /tmp/reviewer-sim-iphone.xcresult test

# iPad compatibility (Apple reviewed Baat on an iPad)
xcodebuild -project BrewDesk.xcodeproj -scheme BrewDesk \
  -configuration Release ENABLE_TESTABILITY=YES \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -only-testing:BrewDeskUITests/ReviewerSimulationTests \
  -resultBundlePath /tmp/reviewer-sim-ipad.xcresult test

# Pull the screenshots out of the bundle
xcrun xcresulttool export attachments \
  --path /tmp/reviewer-sim-iphone.xcresult --output-path /tmp/reviewer-sim-png
```

Release hits the production engine (`https://venuekit-ashen.vercel.app`), so
the run doubles as a live-API smoke.

## In CI

`.github/workflows/reviewer-sim.yml` runs both destinations on every PR, on
pushes to `main`, and on demand, then uploads `reviewer-simulation-evidence`
(both `.xcresult` zips + a flat `screenshots/{iphone,ipad}/` folder, 14-day
retention). Download it from the run's Summary page; open the PNGs directly,
or `open reviewer-sim-iphone.xcresult` for step-by-step detail in Xcode.

The repo is private, so macOS minutes bill at 10×; a run is ~15–20 minutes.
If quota bites, drop `pull_request` from the trigger and keep main + manual.
