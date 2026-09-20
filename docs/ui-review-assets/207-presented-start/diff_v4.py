#!/usr/bin/env python3
"""Objective pass test for bamware-brewdesk#207 (supervisor's spec):

Diff every extracted frame against a reference frame (the first frame
where the settled mark is visible, i.e. the static teal LaunchBackground
plateau before any pulse starts) and split each frame into an upper half
(dot/arcs/ripple) and lower half (cup), counting changed pixels
(diff > 24) in each half separately.

Pass criteria:
- At least 12 consecutive frames with > 300 changed pixels in the upper
  half during the pulse window.
- The lower half (cup) stays < 40 changed pixels until hand-off begins.
- Hand-off then shows a full-frame change.
"""
import glob
import sys
from PIL import Image, ImageChops

FRAMES_DIR = sys.argv[1]
REFERENCE_INDEX = int(sys.argv[2])  # 1-based frame number
START = int(sys.argv[3]) if len(sys.argv) > 3 else 1
END = int(sys.argv[4]) if len(sys.argv) > 4 else None
SPLIT_ROW = int(sys.argv[5]) if len(sys.argv) > 5 else None
DIFF_THRESHOLD = 24

files = sorted(glob.glob(f"{FRAMES_DIR}/f_*.png"))
if END is None:
    END = len(files)
files = files[START - 1:END]
reference_file = sorted(glob.glob(f"{FRAMES_DIR}/f_*.png"))[REFERENCE_INDEX - 1]

reference = Image.open(reference_file).convert("RGB")
w, h = reference.size
half_h = SPLIT_ROW if SPLIT_ROW is not None else h // 2

def changed_pixel_count(im_a, im_b, y0, y1):
    diff = ImageChops.difference(im_a.crop((0, y0, w, y1)), im_b.crop((0, y0, w, y1)))
    px = diff.load()
    count = 0
    dw, dh = diff.size
    for y in range(dh):
        for x in range(dw):
            r, g, b = px[x, y]
            if max(r, g, b) > DIFF_THRESHOLD:
                count += 1
    return count

print(f"reference frame: {reference_file}")
print(f"analyzing frames {START}..{END} ({len(files)} frames)\n")

rows = []
for offset, f in enumerate(files):
    frame_no = START + offset
    im = Image.open(f).convert("RGB")
    upper = changed_pixel_count(reference, im, 0, half_h)
    lower = changed_pixel_count(reference, im, half_h, h)
    total = upper + lower
    rows.append((frame_no, f.split("/")[-1], upper, lower, total))

print(f"{'frame':>5} {'file':>12} {'upper(dot/arc/ripple)':>22} {'lower(cup)':>11} {'total':>7}")
for frame_no, name, upper, lower, total in rows:
    print(f"{frame_no:>5} {name:>12} {upper:>22} {lower:>11} {total:>7}")

handoff_start_index = None
for r in rows:
    if r[3] > 100:  # cup/lower half starts changing = hand-off's own fade beginning
        handoff_start_index = r[0]
        break

pre_handoff_rows = rows if handoff_start_index is None else [r for r in rows if r[0] < handoff_start_index]
max_lower_pre_handoff = max((r[3] for r in pre_handoff_rows), default=0)

# Pulse-window runs: consecutive frames with upper > 300 AND lower still
# quiet (< 40) — i.e. strictly before hand-off, so a long run *during*
# hand-off (where both halves change together) isn't miscounted as "the
# pulse."
consecutive_runs = []
run = []
for r in pre_handoff_rows:
    if r[2] > 300 and r[3] < 40:
        run.append(r)
    else:
        if run:
            consecutive_runs.append(run)
        run = []
if run:
    consecutive_runs.append(run)
longest_run = max(consecutive_runs, key=len) if consecutive_runs else []

full_frame_handoff_seen = any(r[4] > (w * h * 0.3) for r in rows if handoff_start_index is not None and r[0] >= handoff_start_index)

print(f"\nLongest consecutive run of upper-half frames with >300 changed pixels (pulse window, lower<40): {len(longest_run)} frames")
if longest_run:
    print(f"  frames {longest_run[0][0]}..{longest_run[-1][0]}")
print(f"Max lower-half (cup) changed pixels before hand-off: {max_lower_pre_handoff}")
print(f"Hand-off (cup/lower half starts changing) first detected at frame: {handoff_start_index}")
print(f"Full-frame (>30%) change seen at/after hand-off start: {full_frame_handoff_seen}")

passed = len(longest_run) >= 12 and max_lower_pre_handoff < 40 and handoff_start_index is not None and full_frame_handoff_seen
print(f"\nPASS: {passed}")
