#!/usr/bin/env bash
# Assemble submission/<version>/ — the single reviewable folder holding
# everything a store submission ships with (brewdesk#121; pattern for all
# future Bamware apps). Run from the repo root, normally via
# `fastlane store_screenshots`.
set -euo pipefail

VERSION="${1:?usage: assemble_submission.sh <marketing-version>}"
DEST="submission/${VERSION}"

mkdir -p "$DEST"/{screenshots,metadata,evidence}
cp -R fastlane/screenshots/en-US "$DEST/screenshots/"
cp -R fastlane/screenshots/es-ES "$DEST/screenshots/"
cp -R fastlane/metadata/. "$DEST/metadata/"
cp -R fastlane/review_information "$DEST/" 2>/dev/null || true

GIT_SHA=$(git rev-parse --short HEAD)
cat > "$DEST/README.md" <<MD
# BrewDesk ${VERSION} — submission pack

Assembled $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit ${GIT_SHA} by
\`fastlane store_screenshots\`.

- screenshots/ — composed 6.9" store set (1320×2868), en-US + es-ES,
  captured in LIGHT appearance from the Release build on iPhone 17 Pro Max
  with the store surface gated (matches the shipped binary).
- metadata/ — listing text as submitted (source of truth: fastlane/metadata).
- review_information/ — reviewer notes.
- evidence/ — gate results for this pack (test verdicts, capture logs).

Store archive itself comes from a release/${VERSION} branch per
docs/RELEASING.md (committed gate flip, tagged store/${VERSION}-buildN).
MD
echo "assembled $DEST"
