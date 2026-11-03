#!/usr/bin/env bash
# Release smoke — Definition of Done rule 7 (bamware-ai/docs/definition-of-done.md).
# Nothing ships to TestFlight unseen: build the Release app (production engine),
# install it on a simulator, walk every top-level surface, write screenshots
# for the supervisor to READ, and run the live engine contract tests.
#
#   scripts/smoke-release.sh [out-dir]
#
# Exit non-zero on any failure, including a missing Ask tab.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.smoke/$(date +%Y%m%d-%H%M)}"
SIM_NAME="brewdesk-smoke"
mkdir -p "$OUT"
export MAESTRO_CLI_NO_ANALYTICS=1

udid=$(xcrun simctl list devices available -j | python3 -c "import sys,json;d=json.load(sys.stdin);print(next((x['udid'] for v in d['devices'].values() for x in v if x['name']=='$SIM_NAME'),''))")
if [ -z "$udid" ]; then
  udid=$(xcrun simctl create "$SIM_NAME" "iPhone 17")
fi
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null

echo "== Release build (production engine)"
xcodebuild build -project "$ROOT/BrewDesk.xcodeproj" -scheme BrewDesk -configuration Release \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$OUT/dd" CODE_SIGNING_ALLOWED=NO \
  > "$OUT/build.log" 2>&1 || { tail -20 "$OUT/build.log"; exit 1; }
app=$(find "$OUT/dd/Build/Products" -name BrewDesk.app -path '*iphonesimulator*' | head -1)

echo "== Fresh install"
xcrun simctl terminate "$udid" io.bamware.brewdesk 2>/dev/null || true
xcrun simctl uninstall "$udid" io.bamware.brewdesk 2>/dev/null || true
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" io.bamware.brewdesk >/dev/null

echo "== Walk the app"
maestro --udid "$udid" test "$ROOT/scripts/smoke/onboard.yaml" > "$OUT/maestro-onboard.log" 2>&1 || { tail -20 "$OUT/maestro-onboard.log"; exit 1; }
OUT="$OUT" maestro --udid "$udid" test -e OUT="$OUT" "$ROOT/scripts/smoke/tabs.yaml" > "$OUT/maestro-tabs.log" 2>&1 || { tail -20 "$OUT/maestro-tabs.log"; exit 1; }

echo "== Live engine contract tests"
( cd "$ROOT/Packages/BrewDeskKit" && TEST_RUNNER_BREWDESK_LIVE_CONTRACT=1 xcodebuild test -scheme BrewDeskKit-Package \
    -destination "platform=iOS Simulator,id=$udid" -only-testing:VenueKitTests/LiveEngineContractTests \
    > "$OUT/contract.log" 2>&1 ) || { grep -E "✘|error:" "$OUT/contract.log" | head; exit 1; }
grep -q "TEST SUCCEEDED" "$OUT/contract.log"

echo "== Screenshots to READ before uploading:"
ls "$OUT"/*.png
