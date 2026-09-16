# Sheet dismissal: Cancel/Done feel sluggish in the Log sheet and the food form

2026-09-16. The user: tapping Cancel or Done in the Add Food form or the
Log sheet "seems a bit slow to do anything, almost like the tap didn't
register but then does." Noticed only since the 2026-09-15 builds.
Phone: iPhone 16, iOS 27.0.

## Cause

Neither button does anything but `dismiss()`. The delay is the HOST
behind the sheet. `f06e555` (2026-09-15, the tab-bar fix) rewrote
`RecedesBehindSheet` (Style.swift) from a constant-identity
`.blur(radius: isPresenting ? 12 : 0)` into

    Group {
        if isPresenting && !reduceTransparency { content.blur(radius: 12) }
        else { content }
    }

The two branches are different view TYPES, so the switch changes the
content's structural identity: every present and every dismiss tears the
host's whole subtree down and rebuilds it, on the main thread, in the
same transaction that should start the dismissal animation. The repo
already knew this trap twice over — TodayView's pane layout is an
`AnyLayout` specifically so a size-class branch does not destroy the
summary+log subtree (audit 2026-08-17), and `entryDoorBar`'s doc comment
refuses an `if` around the List for the same reason.

What each Cancel/Done rebuilt:

- Log sheet closing over Today: the entire NavigationStack — including
  the `.sheet` slot presenting the very sheet being dismissed,
  `.task { model.start() }`, the onAppear consumers and the
  `DisablesInteractivePop` representable. Scroll offset lost.
- Food form closing over Foods, or any child sheet closing over the Log
  sheet: the List with its `.searchable` drawer, and on the Log sheet
  its `.task` (recent-entries HealthKit query, `buildLibraryItems`,
  `historyItems`) — all re-run at the moment of dismissal.

## Measured, not guessed (27.0 sim, iPhone 18 Pro, HEAD `3a6f4f6`)

`simctl io recordVideo` (VFR, timestamps preserved) with `axe tap`
driving; per-frame mean-abs-diff plus a Cancel-button-region brightness
track (`analyze_sheet.py`, session scratch).

- Portion sheet dismissed by backdrop tap over the Log sheet: the list
  stayed BLURRED with Cancel/Done dimmed and disabled for ~360 ms after
  the portion sheet had visibly left the screen (t=5.78 → 6.14), then
  snapped crisp in ONE frame. The 0.2 s fade the modifier promises never
  happened — the branch swap is a hard cut. A Done tap in that window is
  lost to `.disabled`.
- Cancel on the Log sheet itself (programmatic `dismiss()` over Today):
  ~7 frames (~120 ms) between the button's press highlight appearing and
  the sheet's first movement — on an M-series simulator with a
  near-empty Today. The phone is several times slower and carries a
  real day's rows.
- `simctl io recordVideo` drops its buffered tail on SIGINT when nothing
  moved after the event of interest — two captures ended ~30 ms after
  the tap. Let something move on screen before stopping, or use a
  longer, busier capture.

## Fix

`RecedesBehindSheet` becomes an OVERLAY: nothing touches the content
while idle (so the tab-bar cause — a filter the Liquid Glass bar samples
every frame — cannot return, by construction), and while a sheet is up
an overlay carrying the frosted material plus the dark scrim fades in
and out. Content identity never changes. Reduce Transparency keeps its
stronger flat scrim. DEBUG builds carry a Settings → Appearance picker
(`Sheet recede`: Material / Scrim only) so the user can compare both
looks on the phone from one deploy; the loser is deleted once chosen.

Secondary, separate mechanism, also chosen by the user: the food form's
Log route (`FoodFormView.log`) waited for the HealthKit write, haptic
and reminder replan before `dismiss()`, so after the portion sheet slid
away the form lingered for the write. It now leaves as soon as the
portion sheet has gone (`sheetDidDismiss`, `portionDidLog`); the write
finishes behind it and a failure still shows its "Couldn't log" toast.

## Guard

`testSheetRoundTripKeepsFoodsScroll` (default UI suite, big-library
seed): scroll Foods past its top, open a row's edit form, Cancel, and
the row must still be hittable at the same y. Run once against the
branch form to prove it bites before the fix landed.

## Verification

- Sim: the same recording, press-to-motion frames before/after; the
  un-blur should now fade rather than cut.
- Sim: `testTabBarAnimationProbe` + `scripts/analyze-tab-probe.py`,
  Calendar→Today ×3, must stay in the ~140 ms / 2–3 Foods-frame band
  (the second cause is sim-visible; the first is not).
- Phone: the user's eye on Cancel/Done in both dialogs, and on the tab
  slide — the only instrument for the glass cost.

## Results (2026-09-16, 27.0 sim unless noted)

- `testSheetRoundTripKeepsFoodsScroll` against the branch form: the
  anchored row ("Filler food 20") was GONE from the tree after Cancel —
  the List had been rebuilt and reset to its top. Against the overlay:
  passes, row hittable at the same y.
- Log sheet Cancel over Today, overlay build: the sheet's first movement
  is on the frame after the tap (~1 frame vs ~7 on the branch build),
  and Today behind it — title and toolbar included, which the old
  `.blur` could never reach — fades from frosted to crisp as the sheet
  drops.
- Portion sheet backdrop-dismissed over the Log sheet: the un-frost is
  a ~6-frame fade instead of a one-frame cut; Cancel/Done brighten one
  beat before it. The ~0.4 s between the sheet leaving the screen and
  `activeSheet` going nil is UIKit's transition completion and stays.
- Tab probe (`testTabBarAnimationProbe`, `--tab-probe-no-health`),
  Calendar→Today ×3 on the overlay build: 132 / 153 / 152 ms, 11–12
  frames, Foods-band dwell 3 / 4 / 4 — the same band as the shipped
  2026-09-16 fix (133–148 ms, 3 / 3 / 4). No filter on the content while
  idle, so the device-only first cause cannot come back by construction;
  the user's eye on the phone is still the assertion for that.
- Recede looks, dark mode, portion sheet over the Log sheet: REGULAR
  material hides the list entirely; THIN nearly so; ULTRA-THIN ghosts the
  rows the way the 12pt blur did; SCRIM leaves them crisp but dimmed.
  Ultra-thin is the DEBUG picker's default pending the user's choice.
- The food form's Log route: `log()` now calls `dismiss()` in the same
  turn as the portion sheet's own, so form and portion sheet leave in
  ONE cascade. `testLogWithoutSaving` (`LOG_WITHOUT_SAVING=1`, opt-in,
  not run since the 2026-09-15 drawer move) tapped the Log sheet's Done
  straight after Log and found none — the failure-time hierarchy showed
  the Log sheet back in its ACTIVE-SEARCH state (the dead-end query
  still in the drawer, "No matches" / "Add Food" below), where the
  drawer's search controller shows its own "Close" in place of
  Cancel/Sort/Done (the landmine `plans/PLAN-log-sheet-layout.md`
  measured). Pre-existing; the test now waits for Close, ends the
  search, then waits for Done to be hittable.
