# Community Capture UX — guided contribution flow

Issue: #46 (Epic #25, story 1). Status: spec + DEBUG-only prototype, no upload
wiring. The mock service seam is `CaptureSubmissionService`; real networking is
a later story.

## Who this is for

A non-technical BrewDesk user sitting in a cafe who wants to help. They have
never heard the word "metadata" and will not read a paragraph. The flow must
tell them exactly what to point their camera at, one thing at a time, and thank
them fast. Every screen answers three questions at a glance: *what do you want
from me, why, and how much is left?*

## Principles

1. **One ask per step.** Never show two instructions at once. The shot list is
   sequenced, not a checklist dumped on the user.
2. **Say why, in one line.** People shoot better photos when they know what the
   photo is evidence *for* ("outlets photos power our 'plugs' badge").
3. **Progress is always visible.** A step indicator ("Shot 1 of 3") plus
   filled/empty dots. No spinner ambiguity: instant local feedback after every
   action.
4. **Forgiving.** Retake any shot before submitting. Skipping a shot is
   allowed (venues differ — some have no visible outlets); a skipped shot is
   marked honestly, never silently dropped.
5. **Exit is safe.** Cancel at any point discards cleanly with a confirmation
   only when photos would be lost.

## The shot list (and why each shot)

| # | Ask | Why we need it (shown to user) | Why (product truth) |
|---|-----|-------------------------------|---------------------|
| 1 | **The room from the door** | "One wide shot from the entrance shows people what they're walking into." | Establishes layout, crowding, light; the anchor photo for the venue's workability story. |
| 2 | **The seating area** | "Tables and chairs — where would you actually work?" | Backs seating-type and work-surface claims (bar vs table, laptop room). |
| 3 | **The outlets** | "A wall or floor outlet near seating. No outlets in sight? Skip — that's useful too." | Backs the power-availability claim; an honest skip is a data point (outlets not visibly available). |

Order matters: wide → medium → detail. The easy, non-awkward shot comes first
so contributors commit before the fiddly one.

## State machine

```
guide ──Start──▶ shoot(1) ──photo──▶ shoot(2) ──photo──▶ shoot(3) ──photo/skip──▶ confirm
  │                 │  ▲______retake/skip loops______▲                              │
  └──Cancel──▶ dismiss   (Cancel w/ photos ⇒ discard alert)          Edit ◀─────────┤
                                                                     Submit ────────▶ submitted
                                                                                        │
                                                                                     Done ▶ dismiss
```

States: `guide → shoot → confirm → submitted`. `shoot` carries a step index
(1…3). Back from `shoot(n)` returns to the previous step with its photo intact.
`confirm` can re-enter `shoot(n)` for a single retake.

## Screens

### 1. Guide — "Help map this cafe"

Purpose: set expectations in under 10 seconds; get consent to proceed.

- Header: venue name, so the user is certain what they're contributing to.
- Title: **"Help map {venue name}"**
- Body: **"Three quick photos help remote workers know what to expect.
  Takes about a minute."**
- The shot list rendered as three rows, each with an icon, the ask, and the
  one-line why (from the table above). This is the *only* place the whole list
  appears — it primes the sequence without demanding memorization.
- Privacy line (small, not buried): **"Try not to include people's faces."**
- Primary button: **"Start — 3 photos"** (button states the cost).
- Cancel: toolbar "Cancel", dismisses immediately (nothing to lose yet).

### 2. Shoot — one step per shot

Purpose: get one specific photo. Repeats for steps 1–3.

- Progress header: **"Shot {n} of 3"** + three dots (filled = captured,
  ring = current, empty = upcoming).
- Ask, large: e.g. **"The room from the door"**.
- Why, one line beneath, e.g. **"One wide shot from the entrance shows people
  what they're walking into."**
- Capture area: in the prototype, a PhotosPicker ("Choose a photo") plus a
  DEBUG camera-mock button ("Use sample photo") because the simulator has no
  camera. On device this becomes the camera. After capture, the photo fills the
  area with instant feedback: a checkmark flash and the caption
  **"Got it — {ask}"**, plus **Retake**.
- Primary button: **"Next"** (disabled until this step has a photo); on the
  last step — and when re-entering from Confirm — it reads **"Review"**.
- Secondary: **"Skip this shot"** — always available, styled quiet; it marks
  the slot skipped and advances immediately (one less tap). Copy on the
  outlets step acknowledges the honest-skip case up front.
- Back: returns to the previous shot, photo preserved; from the first shot it
  returns to the Guide.
- Cancel: if any photo exists, confirmation alert — **"Discard your photos?"
  / "Your {n} photo(s) won't be saved." / Discard · Keep going**.

### 3. Confirm — "Ready to send?"

Purpose: let the user check their work once, then commit.

- Title: **"Ready to send?"**
- The three slots as labeled thumbnails (ask as the label). A skipped slot
  shows its label plus **"Skipped"** — visible honesty, no shame copy.
- Tapping a thumbnail returns to that shot's Shoot step for a retake, then
  straight back to Confirm.
- Reassurance line: **"Photos are reviewed before they appear in BrewDesk."**
  (True of the eventual pipeline; sets moderation expectations now.)
- Primary button: **"Submit photos"**. While the (mock) submission runs the
  button shows a progress state and the screen stays interactive-safe
  (controls disabled, no double submit).
- If submission fails (the seam can fail): inline error
  **"Couldn't send your photos. Check your connection and try again."** with
  **Try again** — photos are never lost on failure.

### 4. Submitted — thank you

Purpose: instant gratitude; close the loop.

- Big checkmark (animated once, respects Reduce Motion).
- Title: **"Thank you!"**
- Body: **"Your photos for {venue name} are in review. You just made someone's
  workday easier."**
- Primary button: **"Done"** — dismisses the whole flow. No other exits; the
  job is finished and the screen says so.

## Accessibility

- Every screen's title is a heading (`.isHeader`); VoiceOver lands there first.
- Progress dots are decorative-hidden; the "Shot n of 3" text carries the
  progress semantics.
- Thumbnails have labels ("The seating area, photo added" / "…, skipped").
- All tap targets ≥ 44pt; Dynamic Type respected end to end (no fixed-size
  text); works at accessibility sizes.
- Checkmark/flash animations gated on Reduce Motion.
- Verified with XCUIApplication `performAccessibilityAudit()` on all four
  states.

## Prototype scope (this issue)

- Reachable in DEBUG builds only: toolbar button on the venue detail screen
  (`#if DEBUG`), presenting the flow as a sheet.
- `CaptureSubmissionService` protocol + `MockCaptureSubmissionService`
  (configurable delay/failure) — the seam the real uploader will implement.
  **No networking.**
- Photos via PhotosPicker or a bundled sample generator (camera-mock) so the
  flow is fully drivable in the simulator and in UI tests.
- Shared-UI note: candidates for later extraction to bamware-ios `BamwareUI`
  (step-progress header, photo-slot card) are kept dependency-free to make
  that move cheap. Not extracted in this issue.

## Out of scope

Real camera capture session, uploads/networking, moderation UI, contributor
accounts/attribution, localization (strings are inline pending the flow
settling; xcstrings migration when the real feature ships).
