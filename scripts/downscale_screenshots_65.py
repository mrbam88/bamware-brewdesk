#!/usr/bin/env python3
"""Derive the 6.5-inch (1284x2778) App Store set from the composed 6.9-inch
(1320x2868) screenshots: uniform scale, centered on a canvas filled with the
slide's own background color. Part of the store_screenshots lane."""
import pathlib
import sys
from PIL import Image

TARGET = (1284, 2778)
root = pathlib.Path("fastlane/screenshots")
for locale in ("en-US", "es-ES"):
    src_dir = root / locale
    dst_dir = root / "6.5" / locale
    dst_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    for src in sorted(src_dir.glob("*.png")):
        img = Image.open(src).convert("RGB")
        scale = min(TARGET[0] / img.width, TARGET[1] / img.height)
        resized = img.resize(
            (round(img.width * scale), round(img.height * scale)),
            Image.LANCZOS,
        )
        canvas = Image.new("RGB", TARGET, img.getpixel((2, 2)))
        canvas.paste(
            resized,
            ((TARGET[0] - resized.width) // 2, (TARGET[1] - resized.height) // 2),
        )
        canvas.save(dst_dir / src.name, "PNG")
        count += 1
    print(f"{locale}: {count} -> {dst_dir}")
