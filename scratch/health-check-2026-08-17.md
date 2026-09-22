# Health Check — 2026-08-17 (full sweep, 16 auditors)

Run interrupted mid-flight by an API session limit and resumed; all 16
auditors completed. Every CRITICAL/HIGH finding below was re-verified
against the code by the coordinator before inclusion; calibrations note
where a verdict moved.

Raw auditor tally: 2 CRITICAL / 15 HIGH / ~29 MEDIUM / ~27 LOW.
After verification: 1 submission-blocking CRITICAL, 7 verified HIGHs
worth acting on, the rest calibrated down, refactor-shaped, or
previously adjudicated.

## Verdict

No live crash, data-loss, or corruption path exists in shipped code.
Every auditor's "clean list" held up: prior fixes from the 2.27.x sweep
are intact, both historical crash shapes are not regressed, secrets are
Keychain-only, gating on the 18.6 floor is airtight. What remains is
one compliance gap, a handful of small verified defects, and a long
tail of polish.

## Act on these (verified, ranked)

1. **ShareInbox.clear() destroys other sessions' deposits** — storage
   HIGH, VERIFIED, and simpler than the auditor's version: share menu A,
   extension dies without completing (the exact case the deposit-net
   exists for); share menu B later and complete it in-extension;
   `clear()` sweeps the whole directory and A's queued import is
   silently deleted. Violates `write()`'s own comment ("two menus shared
   before the app is opened must both survive"). Fix: `deposit` returns
   its filename; `clear(only:)` scopes to it. `ShareInbox.swift:179`.
2. **Main-thread image resample freezes the app on paste/screenshot
   import** — concurrency HIGH, VERIFIED. `FoodImageReader.cascade`
   (`FoodImageReader.swift:119`) runs `downsampled(maxEdge: 3000)`
   synchronously under `@MainActor`; the paste door and
   `SharedImageSheet` hand it full-resolution images. Fix is the
   in-repo precedent (`jpegForUpload`'s `@concurrent` /
   `Task.detached`), ~4 lines.
3. **riceToast light-mode text fails WCAG AA** — accessibility HIGH,
   VERIFIED by computation (≈3.3:1 vs 4.5:1 needed; dark mode ≈7.3:1
   fine). It colors the sodium/budget warning text app-wide via
   `sodiumStatus`/`remainingStatus`. riceToast is also the app-wide
   interactive tint, so don't darken it globally — add a darker
   text-variant (`riceToastText`) used by the two status helpers.
   `BrandColors.swift:17`. Design call: pick the darker tan.
4. **OnigiriShare has no PrivacyInfo.xcprivacy** — security CRITICAL
   for App Store submission, VERIFIED absent (only target of five
   without one) while the extension uses UserDefaults
   (`ShareFlow.swift:374` + AIProviderSettings reads). Zero impact on
   device deploys today; blocks the commercialization plan's uploads
   (ITMS-91053). Fix: copy OnigiriWidgets' manifest into OnigiriShare/,
   `xcodegen generate` picks it up.
5. **Today and Calendar disagree on today's deficit target** —
   architecture HIGH, VERIFIED divergence. `TodayView.requiredDeficit`
   deliberately skips the `DeficitTargetHistory` snapshot for today
   (documented stale-stamp bug); `CalendarModel.targetDeficit(for:)`
   still reads the snapshot for today. After a goal edit and before the
   next re-stamp, the two screens can show different targets for the
   same live day — the "never reimplement the rule locally" class.
   Fix: hoist one rule into OnigiriKit; both call it.
6. **LibraryMaintenance repair hardening (three small fixes)** —
   core-data HIGHs, all VERIFIED: (a) the two earliest failure exits
   (nil model bridge, `loadPersistentStores` error) are the only
   unlogged branches; (b) auto-migration flags default true against a
   hand-copied entity list — set both false and derive the list from
   `OnigiriSchemaV1.models`; (c) the share extension opens the same
   store with no repair pre-flight (dormant — it only touches Food —
   but one `repairDanglingFoodReferences` call is cheap insurance).
7. **DaySnapshot's non-Optional Bools can break the sealed-store
   fallback** — codable HIGH, VERIFIED latent. Synthesized Decodable
   ignores `= false` defaults; the next non-Optional field added to the
   struct makes old cached blobs fail decode, `try?` falls through, and
   the widget recomputes live against a store already known sealed —
   the documented "confident zero day" bug's reintroduction path. Fix:
   `Bool?` + treat nil as false (mirror `trackedTotals`).
   `SnapshotLoader.swift:17-22`.

## Worth doing, second tier (verified MEDIUMs)

- **sharedImport vs. an open tab sheet** (nav HIGH → calibrated): the
  drain/onOpenURL paths don't check whether Today/Foods/Add already has
  a sheet up. Typical symptom is deferred presentation (import appears
  after the other sheet closes), not a teardown race — but the deposit
  has already been take()n, so an app kill in that window loses it
  (compounds with the next item). Cheap guard: defer assignment until
  no tab sheet is presented.
- **ShareInbox.take() moves the deposit to tmp before the import is
  confirmed** (storage MEDIUM): kill/jetsam while MenuImportSheet is
  open → share unrecoverable. Copy-then-delete-on-success (or delete
  from the inbox in `SharedImport.cleanUp()`).
- **Watch log delete/edit has neither confirm nor undo** (ux MEDIUM):
  the phone's no-confirm design is justified by its captured-value Undo
  toast; the watch got the no-confirm half only. Mirror the captured
  re-log into `WatchModel` via the existing flash affordance.
- **Screenshot-nutrition read has no golden-set eval** (FM MEDIUM): the
  one AI affordance of seven with no regression gate — and the one with
  the 810,400 mg sodium incident in its history. Copy the sign-read
  eval template.
- **Prompt delimiters on 7 of 8 builders** (FM MEDIUM): apply
  `signUser`'s `---` data-framing to the rest.
- **OnlineFoodSearch.searchTask/pageTask not cancelled on
  FoodFormView/QuickLogSheet dismissal** (memory MEDIUM): mirror the
  sibling `offerTask` pattern in the four handlers. Do NOT use
  `.onDisappear` (documented `.searchable` transient-teardown trap).
- **FoodDataCentral error/network tests** (testing HIGH → MEDIUM):
  4 of 5 error cases and the POST requirement untested; copy
  `OpenFoodFactsNetworkTests`' stub pattern.
- **TodayView regular-width branch loses subtree identity** (layout
  CRITICAL → calibrated MEDIUM): real mechanism, bounded impact —
  collapse state is hoisted and survives; the loss is animations,
  swipe state, and a full re-render on iPad split resize / Pro Max
  rotation. `AnyLayout` fix is small and precedented
  (`TodayCardWidget.swift:284`).
- **Perf quick wins** (swift-perf): COW pull-mutate-writeback in the
  parsers (3 sites, subscript-mutate instead), favorites totals
  computed twice per sync push, LibrarySearch 4-pass → one
  `Dictionary(grouping:)`. All test-covered, none urgent.
- **SwiftUI row-rebuild churn** (perf MEDIUMs): `.equatable()` gating
  for FoodsView/MealFormView rows; per-row detail state for
  `OnlineResultRow` (RowSwipeState pattern).
- **CalendarView.daySummaryCard not VoiceOver-combined** (a11y MEDIUM):
  same fix the file already documents for `slotMetric`.
- **Liquid Glass ports** (5 MEDIUMs): three duplicated `.thickMaterial`
  sheet chromes → one shared gated modifier; ScanSheet overlays must
  use Clear variant over live camera; scopeBar last.

## Calibrated down, declined, or refuted

- **Layout "CRITICAL" and "BROKEN" health** → MEDIUM (above): state
  loss is limited to non-hoisted transients; no crash, no data.
- **Testing "@MainActor on XCTestCase may be a compile break"** → LOW:
  the full scheme compiled and ran today (16/53 gated execution), so
  it's an inconsistency with the target's documented convention, not a
  break. Still worth the 10-minute tidy.
- **ShareInbox TTL sweep** — previously adjudicated this session:
  deliberately no expiry (a sweep silently deletes a user's share).
  Recorded as a product decision, not a gap.
- **Architecture "TANGLED" label** — overstated by its own numbers
  (~90% clean); 3 of its 4 HIGHs are testability/consistency
  refactors (MealDraft extraction, BarcodeRouter Binding→closure,
  MenuImportSheet model extraction), not defects. Good backlog items.
- **Security auditor's prompt-injection reports** — false alarm:
  `ClientIdentity.swift` is a benign 12-line User-Agent helper; the
  "injected" texts were the harness's own session notices. No findings
  were affected either way.
- **Onboarding 6 screens vs 5-screen heuristic** (ux LOW) — skip
  affordance on every screen; leave unless redesigning anyway.
- **UX-flow regression checks** — notification-tap logging, DatePicker
  detent trap, chained sheets: all clean.

## Clean bill (verified by auditors, spot-checked)

SwiftUI performance (0C/0H), memory (no Timer/Combine/PhotoKit at all;
15/16 stored Tasks cancelled), concurrency (READY; both historical
crash shapes intact; zero unchecked-Sendable), Foundation Models
isolation + availability discipline, watch-sync version-skew rules,
LibraryExport round-trip, Keychain/secrets, ATS/entitlements/export
compliance, Liquid Glass gating, navigation destination coverage,
SwiftData test-suite landmine discipline (all 5 container factories
correct), no `try!` anywhere, 610 kit tests / 1,526 assertions.

## Same-day outcome (fix round, evening)

Everything in "Act on these" and the second tier landed, plus the user's
own addition (the paste door's removal). Verification: kit 616/616;
full sim build all five targets; AI eval suite green on the 26.5 sim
(25 executed, 2 designed skips, one documented intermittent that passed
on re-roll); default UI suite run on erased sims before deploy.

What the fixing itself surfaced, beyond the audit findings:

- **The new screenshot eval caught a live invention bug on its first
  run**: the model minted a six-dish menu (plausible calories) from a
  gift-card page, and `plausibleScreenshotFoods` had no grounding
  guard. Fixed: name AND calorie figure must occur in the page's own
  text (the sign read's rule, extended to figures); ungrounded sodium
  is nulled field-wise. Verified by the same eval.
- **The delimiter hardening was A/B-measured, and one builder kept its
  old form**: `describeMealUser` delimited recovers miso's documented
  dropped-rice component but the recovered part's inflated sodium
  fails the meal sodium gate (4/6 vs 5/6). Six of seven builders ship
  delimited; the seventh's verdict is written above the prompt. The
  Big Mac sodium miss exists in both arms — model knowledge.
- **The @MainActor-on-XCTestCase finding ended half-applied**:
  SecretStorageTests and MenuDocumentTests drop it cleanly;
  MenuDishReadTests/MenuSourceReadTests NEED it (sync asserts on
  MainActor app types — removal doesn't compile). Both outcomes are
  documented in the files.
- CLAUDE.md's eval-run destination was stale: two 18.x sims now share
  the "iPhone 16 Pro" name and neither runs the model; the command
  moved to the 26.5 iPhone 17 Pro with a note.

Declined during fixing, with reasons in code: glass on sheet
backgrounds (chrome vs. content — consolidated into `sheetCardChrome()`
instead), the ScanSheet camera-overlay glass port (`.clear` requires a
dimming layer a live viewfinder can't take — needs an on-device
session), and MealFormView row gating (live quantity bindings make a
fingerprint gate a repaint hazard).

## Pre-existing UI-test failures found during tonight's verification

Three OnigiriUITests fail on v2.27.5 exactly as on tonight's tree
(stash-bisected both ways, same assertions, same timings) — none is
tonight's regression, and none had surfaced before because the full
suite always dies earlier on the flow test's stale-seed guard:

- `testSeedGrantAndLogFlow` solo on erased sims reaches the month
  detail and finds neither "Predicted … lb" nor "Scale change … lb"
  (assertions date to July 10; last verifiably green solo run
  unknown). Real missing rows vs. moved labels not yet distinguished
  — external tapping is blocked (axe needs xcode-select at full
  Xcode) and the deep-link probe stalls on the system open dialog.
- `testBarcodeLookupPrefillsForm` can't find the Foods scan row —
  with an "Automation type mismatch … Button vs PopUpButton" runtime
  note that smells like the 26.5 sim's accessibility bridge.
- `testGoalKeyboardDoneDismisses` never sees the keyboard's Done —
  the classic fresh-sim "Connect Hardware Keyboard" default is the
  lead suspect.

All three now run on the iPhone 17 Pro (26.5) pairing; the sims the
suite historically ran on ("iPhone 16 Pro") are now 18.x-only. Next
session: settle sim-environment vs. app regression per test, on
device where needed.

## Review pass — 2026-08-18

The fix list above was re-verified against the tree, item by item, rather
than taken at its word. It holds: all seven "Act on these" and the whole
second tier are present, some under different names than proposed
(`clear(files:)` not `clear(only:)`; `riceToastStatus` not
`riceToastText`; DaySnapshot got a hand-written `init(from:)` with
`decodeIfPresent`, which is better than the proposed `Bool?`). The
contrast figures were recomputed independently and match: the old light
tan is 3.33:1 on white, `riceToastStatus` is 5.44:1.

Three corrections to the record.

- **6(c) never landed, and it should not.** The share extension still
  opens the store with no repair pre-flight, and that is now the
  documented decision (`ShareFlow.saveToLibrary`). The audit's "cheap
  insurance" was `repairDanglingFoodReferences` — the SwiftData-level
  pass, which fetches every Meal and walks `meal.items` / `item.food`.
  The extension touches nothing but `Food`, so it never performs the
  access that trips the process kill; adding that call would MANUFACTURE
  the traversal it was meant to guard. The pass is only safe after the
  Core Data one, which `OnigiriApp` runs first and the extension runs
  not at all.
- **The `sharedImport`-vs-open-tab-sheet guard was never added**, and no
  longer needs to be: the compounding risk was the deposit being
  `take()`n and then lost, and `take()` now copies instead of moving.
  Recorded as resolved by other means, not as done. Separately,
  `onOpenURL`'s file branch assigned `sharedImport` with no guard at all
  (clobbering a live import sheet, whose `cleanUp` then never ran) —
  fixed 2026-08-18.
- **Two of the three UI-test failures were app-side staleness, not the
  simulator**, and both leading suspects in the section above are wrong.
  See below.

### The three UI-test failures, settled

- `testGoalKeyboardDoneDismisses` — **stale test.** The app has no
  "Done": there is no `placement: .keyboard` toolbar anywhere, and
  GoalView's toolbar comment records the removal ("the styled principal
  'Done' read as belonging to nothing") in favour of Cancel ↔ Save, with
  Cancel appearing on focus alone. "Connect Hardware Keyboard" was never
  the cause — a missing software keyboard would have failed the
  assertion one line earlier, and the reported failure was on Done.
  Rewritten as `testGoalCancelDismissesKeyboard` against the real
  contract, asserting Cancel is ABSENT before focus so it cannot pass
  vacuously. It was also missing the `skipOnboardingIfPresent` call six
  sibling tests carry; added.
- `testBarcodeLookupPrefillsForm` — **stale test.** The Foods tab has no
  scan row. `EntryDoorsSection` renders in exactly two places, the Log
  sheet and a blank food form, and `FoodsView` records the 2026-08-02
  removal. The test had been hunting a row that left a fortnight before
  the audit; CLAUDE.md described it too, and both are fixed. The
  "Automation type mismatch … Button vs PopUpButton" note was a red
  herring. Rerouted through Add → Add Food, the same leg
  `testLabelScanPrefillsForm` already uses.
- `testSeedGrantAndLogFlow` — **it was hiding a live app bug.** The
  Calendar's month card did not navigate AT ALL: `.navigationDestination`
  sat one brace too low, on the `NavigationStack` rather than inside its
  content, so it registered with nothing and every value-based
  `NavigationLink` was inert — no error, no log, no warning. Shipped that
  way by the 2026-08-17 switch to a bound `navPath` (so the month-stats
  widget could pop the detail); a bare `NavigationLink(destination:)`
  needs no registration, which is why the older form worked. Four
  different tap strategies were tried against it before the placement was
  found. The month detail was unreachable in the app, not just the test.
  Fixed, verified by tap, and written into CLAUDE.md's SwiftUI landmines.

  Note what this says about the audit round: the nav auditor reported
  destination coverage CLEAN, and by grep it was — the destination
  exists and handles every route. Only its placement was wrong. A
  value-based link is verified by tapping it, never by finding the
  modifier.

  Two test-side faults sat on top of it and had to be cleared before the
  app bug was even visible: the stats rows are nine deep in "This month",
  below the fold, and a List keeps off-screen rows out of the
  accessibility tree; and `firstMatch` on `label CONTAINS 'Predicted'`
  returns the BARE title element (whose `value` is empty), because each
  `LabeledContent` yields two static texts — "Predicted" and
  "Predicted, -0.9 lb". The original one-predicate form was actually
  right about that second element; it never got the chance to match.
  Seeded data was never the problem (-0.9 lb predicted, -1.1 lb actual).

### Verification

Kit 616/616. Full sim build, all five targets. All three previously
failing UI tests pass on erased, paired sims (iPhone 17 Pro / Watch
Series 11, 26.5). Default UI suite: 30 executed, 23 skipped (opt-ins),
every test green except the one below.

**`testSeedGrantAndLogFlow` cannot pass inside the default suite, and
that is structural, not a regression.** Its own stale-seed guard fires:
"the hydration row reads 48 / 64 oz water but a fresh seed yields 24 /
64". `--seed-sample-data` ADDS Health samples on every launch, and
`testFoodsSearchSurvivesScroll` seeds and sorts ahead of it — so the
flow test sees doubled totals. Reproduced with just that pair on erased
sims, with the barcode test out of the picture, so it predates this
session's changes; it is what the "the full suite always dies earlier"
note above was describing. The flow test must be run SOLO on erased
sims, which is how it was verified.

**Resolved the same day.** `seedSampleData` now CLEARS every sample the
app wrote before seeding, so the seed is idempotent and the flow test
runs in the suite: 30 executed, 23 opt-in skips, 0 failures, on a
deliberately un-erased simulator. Clearing rather than de-duplicating is
what makes it work — sibling tests write real logs too (the Add pill's
long press writes 12 oz) and the flow test asserts an exact 24. The
reset is gated `targetEnvironment(simulator)`, not merely `#if DEBUG`:
a DEBUG build reaches the real phone weekly and that store is the user's
diary. On device seeding stays additive. The library half of
`DebugSeeder` was already count-guarded and needed nothing.
