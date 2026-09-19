#!/bin/sh
# Host-side setup for MapLocateButtonUITests' authorized case (bd#185).
#
# `Foundation.Process` isn't available inside an iOS UI-test runner, so the
# simulator's location privacy and simulated GPS fix can't be set from
# Swift test code — they have to be set here, before `xcodebuild test` runs.
# The denied case needs none of this: it uses the existing
# `-UITestLocationDenied` fixture seam.
#
# Usage: scripts/prepare_locate_button_uitests.sh [device-udid|"booted"]
set -eu
DEVICE="${1:-booted}"
BUNDLE_ID=io.bamware.brewdesk
LAT=40.729100
LNG=-73.996500

xcrun simctl privacy "$DEVICE" grant location "$BUNDLE_ID"
xcrun simctl location "$DEVICE" set "$LAT,$LNG"
echo "granted location + set $LAT,$LNG for $BUNDLE_ID on $DEVICE"
