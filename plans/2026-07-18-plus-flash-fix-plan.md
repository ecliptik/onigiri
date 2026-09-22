# Plan — kill the "+" tap flash by intercepting the touch (2026-07-18)

Continuation of `plans/2026-07-18-plus-flash-and-v2.5.12-handoff.md` Part 1.
Read that first: symptom, root-cause chain, and everything already tried
(a–g) live there and are not repeated here.

## The insight this plan is built on

The handoff's leading hypothesis was "the only reliable fix is to make the
'+' NOT a tab" — because SwiftUI transiently renders a tapped tab even when
a custom selection binding rejects it. Every recommended direction therefore
changed the tab bar's appearance (bottom accessory, floating button), which
the user has already vetoed once (step g: the plain-tab "+" "made the menu
bar look off") and which invalidates every device screenshot.

But there is a fix that keeps the tab: **stop the tap from ever reaching the
tab-bar button.** If the touch is intercepted and canceled before the button
fires, the selection never changes, SwiftUI never transiently renders the
`.log` tab, and the search-role activation never starts — no flash, no
morph, no bounce needed on the touch path. The pill keeps `role: .search`
purely for its looks.

**We already have on-device proof this works.** `AddPillLongPress.swift`
installs window-level `UILongPressGestureRecognizer`s with
`cancelsTouchesInView = true` over the pill — and holding the "+" logs water
*without the tab ever activating* (no bounce fires, no add flow opens).
Touch cancellation beats the tab button on real hardware today. A tap
recognizer built on the identical machinery should do the same for taps.

Why the handoff's directions rank lower now (checked against the iOS 26
SwiftUI reference, 2026-07-18):

- **`.tabViewBottomAccessory`** renders a *full-width Music-mini-player bar
  above the tab bar*, not a detached corner circle — wrong look entirely.
  Also: the `isEnabled:` variant is iOS 26.1+, 26.0 had an AttributeGraph
  cycle bug with it, and an iOS 18 fallback would still be needed. Rejected.
- **`Tab(role: .search)` remains the only public API** that renders the
  detached corner circle. There is no "action tab" API. So any non-tab "+"
  is necessarily a look change → full screenshot recapture. Last resort.

## Strategy ladder

- **A (primary): window-level tap interception.** Extend the
  `AddPillLongPress` coordinator with a `UITapGestureRecognizer` per window,
  same pill hit test, `cancelsTouchesInView = true`. On recognition, run the
  add-flow routing directly. Zero visual change, screenshots stay valid.
- **B (fallback): pill-frame overlay.** If recognizer competition can't be
  won (the tab's own internal recognizer fires despite ours), place a
  transparent touch-swallowing `UIControl` exactly over the pill's frame
  (located with the existing `findAddPill(in:)` / corner-region fallback,
  re-synced on layout changes). Same routing, same zero-visual-change win.
- **C (last resort, user-visible): non-tab "+".** Custom floating glass
  button (`.glassEffect()` on 26, plain material on 18) overlaid at the
  corner + remove the search tab. Requires the user's design sign-off FIRST
  and the full screenshot recapture. Only if A and B both fail on device.

## Phase 0 — capture the flash on video (baseline + verify harness)

The handoff notes we never got a frame capture. Do it first — it's the
before/after evidence and the regression check for Phase 2.

1. Boot the iPhone 17 sim (`B9DD19BB…`), build + install the app.
2. Start `xcrun simctl io <udid> recordVideo --codec h264 flash-before.mp4`
   in the background.
3. Drive: launch → Foods tab → tap "+" (XCUITest `switchTab(to: "Add")`, or
   `xcui` tap on the Add button — synthesized touches take the same path as
   fingers).
4. Stop recording; explode frames with
   `ffmpeg -i flash-before.mp4 -vsync 0 frames/%04d.png`; find the flash
   frames. Record *what* actually flashes (bare white `.log` content vs
   tab-bar morph vs both) in this doc.
5. Keep the script in the session scratchpad; Phase 2 reruns it.

**RESULT (2026-07-18, iPhone 17 sim, iOS 26.5):** captured. The flash is the
tab-switch **cross-fade animation**: on tap, SwiftUI animates the full content
area from the Foods screen to the `.log` tab's `Color.clear` (renders white) —
~10 VFR frames of progressive wash-out (frame luma 221 → 231), the tab bar
itself stays solid — then fades back as the bounce reverts and the chooser
sheet slides up. Not a one-frame glitch; a real selection-driven transition.
Confirms interception (prevent the selection) is the right lever. Evidence:
scratchpad `flash-before/` (tap.mp4 + frames).

## Phase 1 — implement interception (option A)

1. **Generalize `AddPillLongPress` → `AddPillGestures(onTap:onLongPress:)`**
   (same file, renamed). One coordinator installs BOTH recognizers on every
   window of the scene; the pill hit test (`shouldReceive`: accessibility
   label → `findAddPill` frame → compact-width corner region) is shared
   verbatim — it is the hard-won, device-proven part.
2. **Tap recognizer config:**
   - `cancelsTouchesInView = true` — on recognition the tab button gets
     `touchesCancelled`, never fires. (`delaysTouchesEnded` defaults true,
     which is what holds the touch-up back until the tap resolves.)
   - Delegate: keep `shouldRecognizeSimultaneouslyWith → true` (don't get
     starved by system recognizers — the long-press lesson), AND add
     `gestureRecognizer(_:shouldBeRequiredToFailBy:) → true` so any
     recognizer-based tab activation must wait for ours and fails when ours
     recognizes. Belt and braces; empirically trim if one suffices.
   - No explicit tap↔long-press dependency needed: a 0.45 s hold begins the
     long press, which cancels the touch and fails the tap; a quick tap
     recognizes before the long press can begin.
3. **Routing:** extract the add-flow routing out of the `.onChange` bounce
   into one `openAddFlow()` on ContentView —
   `selectedTab == .foods ? showAddChooser = true : (selectedTab = .today;
   QuickActions.shared.quickLogRequest = .all)` — called by BOTH the new
   `onTap` closure and the bounce, so the two paths cannot drift.
4. **Keep the `.onChange` bounce as the non-touch fallback.** VoiceOver
   activation, keyboard/Full-Keyboard-Access, and any touch the hit test
   misses (iPad top strip / sidebar, if the label path fails there) still
   select the tab; the deferred bounce routes them exactly as today. Flash
   on those paths is the status quo, not a regression.
5. **Double-fire guard:** if a tap routes AND the tab somehow still selects
   (interception half-works on some future OS), the bounce would route a
   second time (chooser reopening over itself). Latch a timestamp in
   `openAddFlow()` and have the bounce skip routing (bounce only) if a
   tap-initiated routing ran within ~300 ms.
6. Update the big comment block on the `Tab("Add", …)` declaration and the
   handoff doc's Part 1 with the outcome.

Known degradation to accept: a sloppy tap that drifts past the tap
recognizer's movement tolerance fails the tap → the touch reaches the
button → tab selects → bounce routes it (with today's flash). Rare, safe,
identical to current behavior.

**PHASE 1 RESULT (2026-07-18): IMPLEMENTED, flash gone on sim.**
`AddPillLongPress.swift` → `AddPillGestures.swift` (tap + long-press, shared
hit test, `shouldBeRequiredToFailBy` scoped to non-ours recognizers);
ContentView gained `openAddFlow(from:)` + the `lastInterceptedAdd` latch;
bounce kept as the non-touch fallback. After-capture (`flash-after/`):
brightness descends monotonically 221.6 → 185.3 — Foods stays fully opaque
under the arriving chooser sheet, zero white cross-fade. Routing confirmed
(Foods → chooser). `MARKETING_VERSION` → 2.5.13.

**Bug found by the test pass (fixed):** the first cut returned `true` for
ALL simultaneous recognition, including our own tap↔long-press pair. A tap
recognizer has no max duration, so a HOLD logged water at 0.45 s and then
the release ALSO recognized as a tap and opened the add flow — caught by
`testAddPillLongPressLogsWater` ("Log sheet stayed closed" assert). Fix:
exclusive within our pair (`!recognizers.contains(other)`), simultaneous
with system recognizers as before. Also: `testFoodsSearchAfterSave` is
OPT-IN (`TEST_RUNNER_SEARCH_PROBE=1`) — a plain run silently SKIPS it;
set the env or the landmine test proves nothing.

## Phase 2 — verify

1. **Frame capture, after:** rerun Phase 0 → the tap frames must show no
   full-screen flash (pill highlight is fine — that's button feedback).
2. **UI tests** (iPhone 16/17 sim, erased): the full suite, with special
   attention to `testFoodsSearchAfterSave` (the wedged-search landmine —
   interception should moot it, since the search-role activation never
   starts on the touch path, but the test is the arbiter) and every flow
   that calls `switchTab(in:to:"Add")` (log flows, chooser flows —
   synthesized touches go through the interceptor, so these now exercise
   the new path end-to-end).
3. **iPad sim spot-check** (`.sidebarAdaptable`): tap "+" in the top
   strip/sidebar — either the interceptor catches it (label path) or the
   bounce fallback routes it; both acceptable, neither may dead-end.
4. **Minimized-bar check:** scroll Today down so the Liquid Glass bar
   minimizes, tap the shrunken "+" — the live-frame hit test should track
   it; verify routing still fires.
5. **Device deploy** (`scripts/deploy-phone.sh`, watch not needed): manual
   pass — tap "+" from each of the four tabs (Foods → chooser sheet,
   others → Log sheet), long-press → water logs, toggle hold-to-log-water
   off → hold does nothing, VoiceOver double-tap on "Add" still routes.
   The first long-press cut worked under XCUITest but NOT on hardware —
   assume nothing until the device pass is green.
6. **iOS 18 sim smoke test** if one is installed (floor is 18.0): no
   detached circle there, but the interceptor + routing must not break the
   plain tab bar.

**PHASE 2 RESULT (2026-07-18): sim verification GREEN, deployed to phone.**
- Final frame capture on the shipping build: peak luma 221.7 = idle Foods
  brightness (pre-fix peaked 230.8). Zero flash.
- `testAddPillLongPressLogsWater` PASSED (hold → water, sheet stays closed —
  after the pair-exclusivity fix above).
- `testFoodsSearchAfterSave` PASSED with `TEST_RUNNER_SEARCH_PROBE=1`;
  probe: search focus on a SINGLE tap after saving via the "+" chooser —
  the wedged-drawer landmine is clear (interception never starts the
  search-role activation, so there's nothing to abort).
- `testSeedGrantAndLogFlow`: both "+" routes inside it passed (Log-sheet
  water log + Recents), twice. Its one failing assert — line 248 "Water
  rows should be visible once expanded" — REPRODUCES ON STOCK v2.5.12
  (stash-baseline run, same erased sim): PRE-EXISTING test fragility, the
  assert checks existence of the lazily-materialized bottom-of-log Water
  rows BEFORE the scroll loop that reaches them (the delete right after it
  succeeds). Not caused by interception. Follow-up: move the scroll ahead
  of the assert.
- Deployed to the phone (2.5.13-stamped, watch skipped — no watch changes).
  Awaiting on-device confirmation; iPad + minimized-bar + VoiceOver checks
  ride along with it.

## Phase 3 — ship

- Bump `MARKETING_VERSION` → 2.5.13 in `project.yml`, `xcodegen generate`.
- Update: the `Tab("Add")` comment, handoff doc Part 1 (mark resolved, note
  the mechanism), memory hub current-state line.
- Commit (GPG — prime the agent first if needed), push (both remotes ride
  one push), tag if the user wants it as a release.
- **Screenshots: no recapture needed if A or B lands** — the tab bar is
  visually untouched. This UNBLOCKS the paused screenshot backlog
  (handoff Part 4: calendar dark, foods.png re-shoot on the Recent default,
  day-swipe→chevron clips) as an independent follow-up.

## If A fails on device

Work the ladder: B (overlay control over the pill frame — same hit-test
code, view-level instead of window-level), then stop and present C to the
user with the design trade-offs and the screenshot-recapture cost before
building anything. Do NOT re-try the already-falsified approaches from the
handoff table (background-color matching, selection-binding rejection,
role removal without a replacement look).
