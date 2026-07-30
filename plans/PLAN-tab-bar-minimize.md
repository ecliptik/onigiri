# PLAN — the tab bar that won't come back (2026-07-30)

`.tabBarMinimizeBehavior(.onScrollDown)` is currently **`.never`**, shipped
2026-07-30. That is a WORKAROUND, not the destination: the bar sometimes
stayed collapsed to its lone "Today" pill and would not expand again on
scroll-up. This plan is what has to be true before `.onScrollDown` goes back.

## What is PROVEN, not assumed

Checked against the iOS 26 SDK headers directly, not from memory:

- `UITabBarController.tabBarMinimizeBehavior` is the **only** minimize-related
  API in all of UIKit. There is no `isMinimized`, no `setMinimized(_:animated:)`,
  no notification, nothing to read or write the current state.
  (`grep -rn "inimiz" .../UIKit.framework/Headers/*.h` → one file, one enum,
  one property.)
- Apple's own description of the behavior: *"The tab bar minimizes when
  scrolling down, and expands when scrolling back up."* Expansion is a
  **response to a scroll event**, and nothing else.

**Therefore the failure mode is structural, not a race:** the bar expands only
when the tracked scroll view reports scrolling in the opposite direction. In
any state where the user cannot produce that event, the bar stays minimized
and the app has no way to open it. There is no supported escape hatch.

## The failure model

Minimize, then remove the ability to scroll up, and the bar is stranded. The
candidate triggers in THIS app, all needing device confirmation (the user is
the one who can reproduce; each is a distinct suspect, not a guess at one):

1. **Content stops being scrollable after minimizing.** Collapse a section on
   Today, filter Foods down to two rows, delete the last few entries — the
   content is now shorter than the viewport, so there is no scroll-up to make.
   This matches the "gesture-less section expand/collapse" case in the
   2026-07-16 note, which was blamed on Today's day-paging swipe and declared
   fixed when that swipe was removed. The user still sees it, so that
   diagnosis was incomplete: removing the swipe removed *a* perturbation, not
   the structural one.
2. **Tab switch while minimized.** One bar serves all tabs. Minimize on Today,
   switch to Goal (a short Form that may not scroll at all) — nothing there
   can emit a scroll-up.
3. **Sheet dismissal while minimized.** The corner + opens sheets constantly.
   The scroll view underneath emits nothing across present/dismiss.
4. **Content replaced while minimized.** Day paging via the nav chevrons swaps
   Today's content for a fresh copy sitting at the top.

Note 2–4 share a signature: the bar is minimized while the *user's* mental
model says "I'm at the top of a new screen." That is the report — "it doesn't
uncollapse when I scroll back up" — because at the top of unscrollable
content, scrolling up is a no-op that emits nothing.

## Experiments, in order, each with a kill gate

The premise of every candidate fix is unverified, so **E1 gates everything.**

- **E1 — Does toggling the behavior force an expansion?** With the bar
  minimized, flip `.onScrollDown` → `.never` and observe. If the bar expands,
  we have the only force-open primitive available and E2/E3 are worth
  building. **If it does not expand, stop: no fix is possible in SwiftUI, and
  `.never` is the permanent answer** (or the feature goes to a UIKit-hosted
  tab controller, which is a much larger change and probably not worth it).
- **E2 — One-shot flip on the stranding events.** If E1 passes: flip to
  `.never` and back to `.onScrollDown` one turn later, triggered by tab
  change, sheet dismissal, and content-became-unscrollable. Deliberately
  event-driven and momentary — the 2026-07-16 attempt was a *continuous*
  scroll-position-driven flip, which broke the first scroll-down minimize
  (it cannot retroactively minimize a scroll already underway) and went
  sticky on the List/Form tabs. Different trigger profile, same known
  hazards: re-verify BOTH of those regressions before believing it.
- **E3 — Synthetic scroll nudge.** If E1 fails but a programmatic scroll still
  registers with the bar: on the same events, nudge the scroll view a couple
  of points and back via `ScrollPosition`. Only worth trying near the top,
  where the movement is invisible; anywhere else it would yank the user's
  content and is not acceptable.
- **E4 — Guarantee scrollability.** A `minHeight` on tab content so a
  scroll-up always exists. Fixes trigger 1 only, does nothing for 2–4, and
  adds dead space to short screens. Last resort.

## Verification before it goes back

The bug is intermittent, so "I couldn't reproduce it once" is not evidence.
Each of the four triggers gets a deliberate on-device attempt, and the two
historical regressions (first scroll-down minimize works; no stickiness on
the List/Form tabs) get re-checked, since E2 re-enters the exact territory
that was reverted twice. Simulator scroll-phase behavior has already proven
untrustworthy for this bar — device only.

## Recommendation

Leave `.never` shipped while this is investigated. It costs a visual flourish
and costs the user nothing else; the collapsed-forever state cost them a
readable tab bar with no way back. Restore `.onScrollDown` only if E1 passes
AND E2 survives all four triggers plus both historical regressions on device.
