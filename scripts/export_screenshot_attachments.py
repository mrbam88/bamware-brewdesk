#!/usr/bin/env python3
"""Export the AppStoreScreenshotTests attachments from an .xcresult into a
raw-screenshot directory, named by their capture names (NN-slug.png).

Usage: export_screenshot_attachments.py <path.xcresult> <out_dir>

Part of the fastlane :store_screenshots lane (brewdesk#121); reusable for
any app whose capture tests name attachments like "01-slug".
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

xcresult, out_dir = sys.argv[1], pathlib.Path(sys.argv[2])
out_dir.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run(
        ["xcrun", "xcresulttool", "export", "attachments",
         "--path", xcresult, "--output-path", tmp],
        check=True, capture_output=True,
    )
    manifest = json.load(open(pathlib.Path(tmp) / "manifest.json"))
    exported = 0
    for item in manifest:
        for att in item.get("attachments", []):
            human = att.get("suggestedHumanReadableName") or ""
            match = re.match(r"^(\d{2}-[a-z0-9-]+)", human)
            if not match:
                continue
            src = pathlib.Path(tmp) / att["exportedFileName"]
            dst = out_dir / f"{match.group(1)}.png"
            shutil.copy(src, dst)
            exported += 1
    print(f"exported {exported} screenshots to {out_dir}")
    sys.exit(0 if exported else 1)
