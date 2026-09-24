# Salvaging the 2026-09-14 health-check audit

The audit's second half never landed. It sat in a stash (`stash@{0}`,
"wip: pre-existing uncommitted work", 2026-09-15) whose base commit
predates the 2026-09-22 history reset, so it cannot be applied — main
has moved under every file it touches. This plan re-does the parts worth
keeping, BY HAND, against current main, and says what was left behind.

## Step 0 — keep the source before dropping the stash

The stash is the only copy of the new files below (they were untracked,
so they live in its third parent). Pin it to a local ref first so
dropping the stash loses nothing:

```sh
git update-ref refs/salvage/audit-2026-09-14 'stash@{0}'
git stash drop 'stash@{0}'
# read a stashed NEW file:      git show refs/salvage/audit-2026-09-14^3:<path>
# read a stashed EDIT as diff:  git diff refs/salvage/audit-2026-09-14^1 refs/salvage/audit-2026-09-14 -- <path>
```

The ref is local and never pushed. Delete it (`git update-ref -d …`)
once every step below has shipped or been declined.

## Scope

In — five independent steps, each its own commit, in this order
(cheapest and least risky first):

1. Swipe-to-Edit tint → `riceToastStatus`
2. Add pill tap haptic
3. `DateFormatter` → `FormatStyle` (ContentView, BackupService)
4. `ShareAttachmentPicking` + `ScannedProduct.parsedLabel` into the kit
5. `WatchModel` injectable + an `OnigiriWatchTests` target

Out, decided 2026-09-24:
- The `FoodFormView` / `QuickLogSheet` / `TodayView` section
  extractions. Pure textual refactors on files that have churned since;
  redoing them from scratch is cheaper than porting, and nothing is
  wrong without them.
- The `FoodIntelligenceEvals.swift` → `FoodIntelligenceTests.swift`
  rename (and the four plan-doc path edits that followed it). The eval
  file has changed since; CLAUDE.md and the plans all say "Evals".

## 1. Swipe-to-Edit tint

`FoodsView.swift` — the meal row's and the food row's Edit swipe action
(`.tint(.riceToast)`, currently ~L547 and ~L627) → `.tint(.riceToastStatus)`.

Why: the swipe draws a WHITE pencil glyph on the tint fill — on iOS 26
the "Edit" caption sits BELOW the pill in gray, off the fill (seen in
the 2026-09-24 captures), so the bar is WCAG's 3:1 for non-text, not
4.5:1 for text. In light mode `riceToast` (0.72/0.51/0.25) leaves white
at ≈3:1, on the line; `riceToastStatus` (0.55/0.38/0.17) gives ≈5.4:1. The token
already exists for exactly this job (`BrandColors.swift`), and
ContentView already uses it as a tint.

Known gap, NOT fixed here: in dark mode the two tokens are identical
(the bright tan), and white on it is well under AA. Fixing that needs a
new token (a dark-mode fill for white labels), not a reuse — leave a
one-line comment saying so, as the stash did, and don't invent the
token in this commit.

Verify: `testEditSwipeTintShots` (`TEST_RUNNER_EDIT_SWIPE_SHOT=1`)
reveals the swipe on a food and a meal in both appearances and attaches
four shots. Done 2026-09-24 on the 26.5 sim: light mode is a dark brown
pill under a crisp white pencil; dark mode is the unchanged pale tan,
which is the gap above. The Favorite pill beside it (white star on
yellow) is weaker than either in both modes — same token question,
not in this step.

## 2. Add pill tap haptic

`AddPillGestures.swift`. `cancelsTouchesInView = true` on the window
recognizers is what lets the pill's tap and hold both work, but it also
swallows the tab button's own press feedback, so the pill feels dead
(the user, 2026-09-15: it used to look pressed and give haptic
feedback; now it "feels/looks flat").

Change: the coordinator holds a `UIImpactFeedbackGenerator(style: .medium)`,
`prepare()`s it where the recognizers are installed, and fires
`impactOccurred()` in `tapFired` BEFORE `onTap()` — the haptic belongs to
the touch, not to the sheet's presentation that follows.

Open question: should the LONG PRESS fire one too (at `.began`)? It
logs a serving outright, and `LogActions.didMutate` already plays a
notification haptic when a write succeeds, so a press tick there would
double up. Default: tap only; the long press keeps its success haptic.

The VISUAL press state is not part of this. The stash's doc comment
records three on-device attempts that all failed (the SwiftUI hosting
view re-asserts itself over any sibling subview each frame); the only
untried route is a separate always-on-top `UIWindow`. Carry that
comment block over so the next attempt starts from it.

Verify: device only — the simulator has no haptics. Tap the pill: one
tick, sheet opens. Hold: no tick at press, success haptic after the log.

## 3. `DateFormatter` → `FormatStyle`

Two fixed-format, fixed-locale formatters:
- `ContentView.deepLinkDay` (`yyyy-MM-dd`, parses the `day` query item
  of the Today deep link) → `Date.ParseStrategy` with
  `en_US_POSIX` and `.current` time zone; call site becomes
  `try? Date(raw, strategy: Self.deepLinkDay)`.
- `BackupService.stampFormatter` (`yyyy-MM-dd-HHmmss`, the backup file
  name) → `Date.VerbatimFormatStyle` with a Gregorian calendar and
  `.current` time zone; call site `Self.stampFormat.format(now)`.

The kit already uses `VerbatimFormatStyle` this way
(`DebugDiagnosticsLog`, `WidgetBurnGate`, `HealthKitService`) — match
those.

Why bother: a `DateFormatter` is non-`Sendable` shared mutable state,
and this is the idiom the rest of the code already moved to. Not a bug
fix; keep the commit tiny.

The one real risk is a silently different string. The backup name MUST
stay byte-for-byte `onigiri-backup-2026-09-24-134501.json` — the
"newest backup" lookup sorts by modification date, not name, but users
see these names in Files. Add a kit-level test (or a DEBUG assertion)
pinning both formats for a fixed date, including a date whose hour is
before 10 (zero-padding, `.zeroBased` 24-hour clock) and one in a
non-Gregorian device calendar. Round-trip `2026-09-04` through the
parse strategy.

## 4. Share-extension logic into the kit

The extension has no test target, so its two bits of real logic move
into OnigiriKit, where `swift test` covers them.

- New `ShareAttachmentPicking.imageAttachmentIndex(registeredTypeIdentifiers:)`
  — pure over `[[String]]`: the first CONCRETE image type across
  providers in order, skipping bare `public.image` (it conforms but
  can't be loaded). `ShareViewController.imageAttachment(in:)` becomes
  a thin wrapper mapping `providers.map(\.registeredTypeIdentifiers)`.
- `ScannedProduct.parsedLabel` — today a `private extension` at the
  bottom of `ShareFlow.swift` (~L336) — moves to
  `ScannedProduct+ParsedLabel.swift` in the kit as `public`, deleted
  from ShareFlow. Its job is the two "empty string → nil" conversions
  (name, serving) and carrying `warnings` through to `LogConfirmSheet`.

Check before moving: `FoodIntelligence.swift` declares its own
`parsedLabel` on nested types (~L328, ~L614) and `FoodImageReader`
uses `\.parsedLabel` on those. They are different types, so a public
`ScannedProduct.parsedLabel` must not collide — confirm with a full
app + extension build, not the kit build alone.

Tests (from the salvage ref, `Packages/OnigiriKit/Tests/OnigiriKitTests/`):
`ShareAttachmentPickingTests` (6: concrete type picked, abstract skipped,
nil when none, nil on empty, first provider wins, unknown identifier
skipped) and `ScannedProductParsedLabelTests` (4: fields carried, empty
name → nil, empty serving → nil, warnings ride through). Re-read them
against current `ScannedProduct`/`ParsedLabel` — fields may have been
added since 09-14.

Verify: `swift test` (read the executed count), full app build, then
one real share from Photos and one screenshot share on the sim.

## 5. `WatchModel` testable + `OnigiriWatchTests`

The watch app has no tests at all. `WatchModel` news up its own
`HealthKitService`, so nothing can drive it without real HealthKit.

**Seam.** A kit protocol, `WatchHealthWriting` (`@MainActor`,
`Sendable`), listing exactly the calls `WatchModel` makes, with
`HealthKitService` conforming through an EMPTY extension — the protocol
copies the service's signatures, so nothing about the service changes.
`WatchModel.init(health: WatchHealthWriting = HealthKitService())`.

**Redo the method list against today's WatchModel, not the stash's.**
Since 09-14 WatchModel gained `diagnoseIntake(for:)` (DEBUG
diagnostics) and an undo path that calls the full `logFood`. Protocol
requirements cannot carry default arguments, so every call site that
leans on a default (`logFood` without `date:`/`aiGenerated:`/`quantity:`,
`logWater(oz:)`, `todayFoodEntries()`, `dayTotal(of:)`) must pass them
explicitly — `.now`, `false`, `1`, `[]`. That is mechanical but it is
where a behaviour change could slip in: each explicit value must equal
the default it replaces. For `diagnoseIntake`, prefer keeping it off
the protocol (`(health as? HealthKitService)?.diagnoseIntake…` inside
the existing `#if DEBUG`) so a DEBUG-only probe doesn't widen the seam.

Check isolation: `HealthKitService` is a `public final class`; the
protocol is `@MainActor`. Confirm the empty conformance compiles under
the kit's settings with no `@preconcurrency` or `nonisolated` escape
— if it needs one, stop and look rather than paper over it.

**Target.** In `project.yml`: `OnigiriWatchTests`, `bundle.unit-test`,
`platform: watchOS`, sources `OnigiriWatchTests`, depends on
`OnigiriWatch`, `GENERATE_INFOPLIST_FILE: YES`. The stash set
`SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated` like the other test
targets; keep that. Add it to the `OnigiriWatch` scheme's build
(`[test]`) and a `test:` block. Then `xcodegen generate` — and read the
`Executed N tests` line, never the banner (CLAUDE.md, Build and test).

**Tests** (salvage ref, `OnigiriWatchTests/`): `FakeWatchHealth` (records
writes; `nextError`, `failDeleteForId`, `writeDelay`) and
`WatchModelTests`, ten cases — water log success/failure, delete offers
undo, undo re-logs the captured entry, delete failure offers no undo,
edit scales sodium and nutrients with kcal, edit rolls back the new
write when the old delete fails, a synced meal's fields map into the
write, meal log failure, and a second log while one is in flight is
refused. Port them to today's model (the undo path's arguments, the
flash strings), and add one case for today's undo if the stash's
doesn't cover it.

Watch-specific traps: `WKInterfaceDevice.current().play` runs in tests
(harmless on the sim); `refresh()` calls `DailyPlanLoader.load`, which
reads real HealthKit regardless of the fake — tests must assert on the
fake's recorded writes and the flash, never on the plan. If a test
needs the plan, that is a second seam and a separate decision.

Verify: `xcodebuild test -scheme OnigiriWatch` on a watch simulator
passed by `id=`, executed count = 10+. Then deploy to the real watch
and log water + a meal once — the injectable init must not change what
ships.

## Status, 2026-09-24

All five built and tested on the sim; nothing committed yet.

1. Tint — done, four captures looked at (see its Verify).
2. Haptic — in; the tick is DEVICE-ONLY and still unfelt.
3. FormatStyle — `DateStampFormatTests` (app-hosted, 5 tests) holds both
   formats to the formatter each replaced, over a year of hourly stamps
   and a spread of good and bad day strings. The backup name matches to
   the byte. It found ONE difference, kept on purpose and pinned: the old
   formatter read "2026/09/04" (ICU accepts any separator), the strict
   parse refuses it. Both constants are `nonisolated` — the app's
   MainActor default otherwise walls them off from the tests.
4. Share logic — kit suite 794/794 including the 10 moved tests; app +
   extension build clean. A REAL share (Photos, and a screenshot) is left
   for the device.
5. Watch — `OnigiriWatchTests`, 10 tests on the watchOS 26.5 sim. The
   undo test now checks the WHOLE restored entry (quantity, meal
   composition, time, ✨) and polls instead of sleeping; bite-checked by
   dropping `mealItems` from `undoDelete` — it failed, then passed
   restored. Swift Testing names need the trailing `()` in
   `-only-testing:`, or the filter matches nothing and the run is green
   having run zero tests. Deploy to the watch still pending.

Found while porting, kept exactly in the port, FIXED in its own commit
the same day (`editEntryKeepsAMealsComposition`, red before the fix):
`WatchModel.editEntry` re-logs with `mealItems: []`, so resizing a
logged MEAL on the watch strips its composition — the phone's
`LogActions.editFoodEntry` carries `entry.mealItems` through. That is
the three-keys rule in CLAUDE.md, broken on the watch.

## Done when

All five are committed (or explicitly declined here with a reason), the
kit, app and watch suites report their executed counts, and
`refs/salvage/audit-2026-09-14` is deleted.
