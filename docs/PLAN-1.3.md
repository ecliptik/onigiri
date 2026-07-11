# Onigiri 1.3.0 — iPad

Plan agreed 2026-07-11. Same rhythm as 1.1/1.2: implement → kit tests +
affected UI test on ERASED sims → commit → push → deploy → tell Micheal
what to verify. iPad verification is SIMULATOR-ONLY this release
(Micheal's call) — device deploy and the Health-iCloud-sync check move
to whenever an iPad joins `scripts/local-devices.env`.

Decisions locked with Micheal:

- **Library on iPad = Export/Import JSON** (free team: no CloudKit, and
  WatchConnectivity is phone↔watch only). HealthKit *logs* reach an
  iPad via iCloud Health sync on their own; the SwiftData *library*
  travels by the existing JSON export through Files/iCloud Drive.
- **Layout = comfortable adaptation**, not a split-view redesign:
  readable-width columns, wider grids where natural, everything sane in
  Split View/Slide Over.
- **Full multitasking**: all orientations, Split View, Slide Over,
  Stage Manager. No UIRequiresFullScreen.
- Paid account/CloudKit stays deferred (own design cycle).

Starting point worth knowing: `TARGETED_DEVICE_FAMILY` has been "1,2"
since day one (xcodegen default), so the app already installs on iPad —
nothing has ever been tested there. HealthKit exists on iPadOS 17+;
sims get data from `--seed-sample-data`.

## M1 — Foundation + audit

- Make iPad intent explicit in `project.yml` (device family, all four
  iPad orientations; iPhone stays as-is).
- Run the full QA walkthrough + flow test unchanged on an iPad
  simulator (13" and 11") to inventory reality: layout breakage, tab
  bar idiom differences (iPad renders the tab bar at the top — XCUITest
  queries may need `tabBars` fallbacks), sheet presentation, anything
  that crashes. Screenshot sweep IS the audit; fix only blockers here.

## M2 — Comfortable adaptation

- Readable width: Today's and Calendar's ScrollView content capped
  (~700pt, centered) so single columns don't stretch edge to edge.
- Grids breathe in regular width: meter grid, calendar month cells;
  hydration row spacing.
- Forms and sheets: verify iPad presentations (centered cards / form
  sheets), PortionSheet detents, QuickLog sheet width; toast position
  and width cap.
- Compact widths (Split View/Slide Over) reuse the iPhone layouts —
  verify, don't rebuild. `horizontalSizeClass` only where something
  genuinely needs it.

## M3 — Library onboarding on iPad

- Foods' empty state (and the Log sheet's) gains the transfer story:
  "Import your library: iPhone → Settings → Export library, save to
  iCloud Drive, then Import here." with an Import button inline.
- Verify export → Files → import round-trip on the iPad sim.

## M4 — iPad QA pass

- QA walkthrough (normal + accessibility text) on iPad sim, portrait
  and landscape; a Split View–width spot check.
- Review every capture like the 1.1 QA round; fix findings; judgment
  calls to Micheal.
- Flow test green on BOTH iPhone and iPad sims becomes the standing
  gate for layout-touching changes this release.

## M5 — Release

- README: one iPad screenshot (optional row) if the layouts photograph
  well; bump to 1.3.0; tag `v1.3.0`; deploy phone + watch (iPad device
  deploy deferred).

## Out of scope

CloudKit/paid account, true split-view iPad redesign, iPad-specific
widgets/keyboard shortcuts/pointer effects, on-device iPad validation.
