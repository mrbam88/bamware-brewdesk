# BrewDesk product critique — 2026-09-12 (day of App Store approval)

Whole-app critique, judged as a user and as a business, not just as pixels.
Method: Release build from `main` (production Venue Engine) on an iPhone 17 Pro
simulator, driven through every screen in four scenarios (NYC with location,
Cupertino, Austin plus rural Vermont, location declined), 80 screenshots, plus
direct measurement of the live dataset via `/v1/venues/search`, and the public
App Store listing via the iTunes lookup API. Screenshot set and data script are
in the session job dir; key frames are reproduced in the companion web page.

Caveat: the `main` build has the store surface gate OFF, so Sign In, "Rate this
visit" and Contact & Content Rules are visible here but are not in build 19.

## The one-line verdict

The app's promise ("every score shows its work") is stronger than its data. In
NYC the promise is true for about 21 venues. Outside NYC it is an empty promise
with a number on it. Polish the pixels second; fix what the user is shown first.

## Measured facts (2026-09-12)

| Sample (200 venues each) | Laptop policy known | of which researched | Seating known | Outlets known | Websites | Score range |
|---|---|---|---|---|---|---|
| NYC, top by score, 5 km | 200 | **21** (179 are estimates) | 0 | 155 | 0 | 56–72 |
| NYC, nearest first, 5 km | 83 | 9 | 6 | 126 | 0 | 39–69 |
| Cupertino, 10 km | **0** | 0 | 0 | 0 | 0 | 50–55 |
| Austin, 10 km | **0** | 0 | 0 | 0 | 0 | 50–55 |

Engine health: 2,783 venues, 50 baseline metros, 2,144 with photos, dataset
seeded 2026-08-23. Store listing: 5 screenshots, 0 ratings, 2.9 MB, iOS 17+.

## Ranked findings

Severity: **P0** product-defining, **P1** trust or a real bug, **P2** polish.

### P0 — product and business

1. **Ranking by unknowns.** Outside NYC every venue is an estimate at 0%
   confidence and scores 50–55. Cupertino's list reads 55, 55, 53, 52, 50: a
   list of every café sorted by nothing. A number that means nothing costs
   trust the moment a user compares two spots. Fix: no score where confidence
   is 0. Sort baseline cities by distance and "open now", show the facts we do
   have (hours, Wi-Fi from OSM), and say "not checked yet — be the first".
2. **Estimates dressed as facts.** Starbucks Tribeca shows "Outlets: Plenty ·
   Laptop policy: Unrestricted · Noise: Quiet" at 30% confidence. The only
   tell is red-brown text, a code no user knows and one a red-green colorblind
   user cannot see. A user walks there, finds no outlets, and the app lied.
   Fix: estimates render as a visibly different thing ("Probably plenty" with
   a question mark, or folded into "Unknown — help us check").
3. **Data depth versus the pitch.** "2,700+ work spots with a transparent
   Work Fit score" is true in count only: 21 of the top 200 NYC venues carry
   researched claims; seating, the second-heaviest weight in the formula, is
   unknown for every one of them. Fix: spend the $10/month research cap on
   depth not breadth. Top 30 venues in the 5 biggest metros beats 50 metros of
   nothing. Ship the built-but-gated "Rate this visit" so users fill the gaps.
4. **The score is the hero but it cannot separate anything.** Scores compress
   into 50–72; nothing reaches the "75+ great" band the legend promises. 72 vs
   69 tells a user nothing. Fix: lead with the answer, not the number: a
   one-line verdict built from claims ("Good for a 3-hour session: laptops OK
   all day, plenty of outlets, Wi-Fi fast"), with the score demoted to a chip.
5. **No reason to come back.** After one browse nothing changes: no "open
   now near me" on cards, no walking distance, no time-of-day (cafés are
   laptop-hostile at lunch, fine at 3 pm), no live signals. Retention is the
   scoreboard we agreed on. Fix: distance and open-now on every card; make
   laptop-policy time windows visible; ship community ratings and photos.
6. **The out-of-NYC first impression is the whole US market.** Banner text
   "Baseline data here — not yet researched. NYC is fully researched." tells a
   Cupertino user this app is for someone else. Rural Vermont shows "No spots
   in this view · Browse NYC", a fallback 300 miles away. The store subtitle
   "NYC WFH cafés, with evidence" auto-rejects most shoppers. Fix: banner
   becomes an invitation ("We research cities as people ask. Request
   Cupertino"), wire the existing seed-on-demand idea (venue-engine#44),
   and rewrite the subtitle for the work-from-anywhere buyer.

### P1 — trust and real bugs found in this run

7. **Map lost every pin** after clearing a search; the header still said
   "100 of 2,783", the locate button did nothing, only a relaunch fixed it.
8. **Search text never clears.** It survives tab switches and relaunch, and
   new typing appends ("Housing WorksStarbucks" → "No spots in this view").
9. **Search does not move the map to the result.** One hit for "Housing
   Works" while the map still shows North Bergen, NJ, with no pin in view.
10. **Filter popover cannot be dismissed by tapping outside**; only the
    filter button closes it. With "Laptop friendly + Fast Wi-Fi" the top
    results score 59, lower than the unfiltered 72, which looks wrong to a
    user even if the logic is defensible. Needs a check.
11. **Same-name venues look like duplicates.** "Think Coffee" appears twice
    in a row with no address or distance on the card.
12. **Baseline detail header is broken copy.** Cupertino shows "San
    Jose-Sunnyvale-Santa Clara, CA · San Jose-Sunnyvale-Santa Clara, CA"
    where a user wants "Cupertino". Photos show "unavailable · Retry".
13. **Dark mode.** The Spots tab label is nearly invisible; the shelf stays
    light and translucent over a dark map.
14. **Declined location, "Use Union Square instead" path.** Map tiles were
    blank (beige grid with floating dots) in that capture.
15. **Every photo links out to Google Maps**, the competitor, and every
    photo is a Google photo. Legally fine, strategically wrong. Community
    photos with our own attribution are already designed (brewdesk#25).
16. **Business info is empty.** 0 of 200 venues have a website or phone; the
    Info card is hours only, although the business-info ticket is closed.
17. **The You tab greets a first-time user with "Welcome back" and a
    password form** (gated in the store build, but this is what ships when
    the gate opens). No value proposition for an account is shown.

### P2 — polish

18. **Onboarding is three marketing pages** before a map. Four taps to
    value. One page plus the location choice is enough.
19. **Detail card wastes the first screen.** Name shown twice (brewdesk#142),
    "How scoring works" above the fold on every venue; the answer ("can I
    work here?") is below it.
20. **Icon-only facts on cards** ("Fast", "Plenty") make new users guess.
21. **Pin colours are green / olive / brown / red**, so the map, the primary
    surface, is unreadable for red-green colorblind users, including the
    founder. Use shape or number, or a blue-orange scale.
22. **Engineer language in user copy.** "Unverified estimate · 0%
    confidence", "Estimates stay labeled". Users want "We haven't checked
    this one yet."
23. **No rating prompt.** Zero App Store ratings; ask after a save with the
    system review prompt. Free.
24. **Onboarding headline** ("Your next desk might serve espresso") is
    charming but says café, while the product now means libraries and parks.

## What is already good (keep)

Cold launch to pins in about 2 seconds. Clean visual system. Honest
provenance concept, and the methodology page is genuinely well written.
No account needed. Hours with "Open now". Saved list, Directions, Share.
Import from Google Takeout on-device. The rate-this-visit form (five taps,
no typing) is the right shape.

## Recommended polish sprint, in order

1. Fix the four bugs: vanishing pins (7), sticky search (8), search does not
   pan (9), blank tiles on the Union Square path (14).
2. Rework the unknown experience: estimates visibly "not checked yet", no
   score at 0% confidence, baseline cities sorted by distance and open-now.
3. Cards: walking minutes and open-now on every card; detail leads with a
   plain-English verdict; score becomes a chip.
4. Colorblind-safe pins and score chips; dark mode pass.
5. Open the gate: community ratings and photos ship, with the You tab
   explaining why an account is worth having.
6. Data: research top 30 venues in the 5 biggest metros first, inside the
   $10/month cap; then the outside-NYC banner becomes an invitation and the
   store subtitle drops "NYC".
