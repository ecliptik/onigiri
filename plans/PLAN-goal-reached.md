# PLAN — Reaching the target: criterion, celebration, what next (2026-08-10)

**Status: BUILT 2026-08-10.** Parts A–E shipped as specified; milestones
and post-Maintain regain remain deliberately out.

Verified on the 26.5 sim end to end, against a seeded met goal
(`--seed-goal-reached`, new: target 205 with a stamped 210 lb start
against the seeder's 202 → 200 lb weigh-ins, since the criterion cannot
otherwise be reached without a month of simulated loss):
- the Today card reads "🍙 You hit your target / 10 lb down · Choose
  what's next", and the Daily budget card beside it flips to
  "48% · 1,100 of 2,128 kcal eaten" — the zero-deficit-at-target
  behavior, visible;
- Goal shows "You've reached your target — nice work. / 10 lb down since
  Jun 11" over the three chips and Switch to Maintain;
- **"5 lb more" → target 200, date Sep 14 (1 lb/week), and Progress
  since STAYS Jun 11 / 210.0 lb** — Part D, which is the whole point:
  without `.keep` that re-stamps to today;
- ✕ dismisses the card, and it is still gone after a relaunch.

Two things moved during the build:
- the chips wrap to two lines ("5 lb / more") inside a
  `LabeledContent`'s trailing slot, so the label sits ABOVE them;
- Today's detail line routes through `GoalProgress.resolve` rather than
  reading `startWeightLb` directly, so a goal predating the stamp still
  reports its arc and the two surfaces can't disagree.

The ask (the user): decide what it MEANS to hit the goal ("at under
weight for X days maybe?"), celebrate it, and offer the two real next
moves — lose more, or maintain.

## Current state (verified in code)

There is a celebration, and it is one line deep:

- `GoalView.goalReached` (`GoalView.swift:177`) is true the moment the
  scale reads at/below target. It compares `currentWeightLb`
  (`:55` — `model.healthWeightLb ?? manualWeightLb`, the RAW last
  weigh-in), while the plan beside it is derived from `planWeightLb`
  (`:66` — `model.basisWeightLb`, the smoothed basis). **One low morning
  fires the celebration off a reading the budget deliberately ignores.**
  The two screens disagree by construction.
- When it fires: a green seal, "You've reached your target — nice
  work.", and a single `Switch to Maintain` button
  (`GoalView.swift:570`). There is no "keep going" path, and nothing
  outside the Goal screen ever mentions it.
- Do nothing and the app quietly stops asking:
  `requiredDailyDeficit` is `max(0, current − target) × 3500 / days`, so
  at/below target it is **0** and the day's budget becomes the full
  `dayBurn`. Maintenance by arithmetic, in `lose` mode.
- That drift is NOT the same as choosing Maintain, and the difference is
  invisible: `DeficitTargetHistory` stamps 0 for a zero-deficit day,
  which means "no goal — ANY deficit earns the badge", while Maintain
  stamps the sentinel that invokes the band rule (a day far UNDER
  maintenance fails it). Sitting undecided is the most permissive
  grading the app has.
- Editing the target re-stamps the journey start (`GoalUpsert.swift:63`,
  `targetChanged`), so a second goal zeroes the progress bar and the
  lifetime arc disappears at the moment it was earned.

## Decisions (settled 2026-08-10, the user)

1. **Met = the 7-day basis is at/below target AND at least 3 of those
   days were weighed** — with the window WIDENING when it can't find 3
   (decision 5).
2. **Celebration is a dismissible Today card + the Goal section.** No
   launch sheet.
3. **Continuing keeps the original journey start** — one arc, not two.
4. **In-app only.** No notification, no new reminder kind.
5. **A sparse weigher must not be locked out.** 3-in-7 is unreachable
   for anyone weighing weekly, which would make the celebration
   impossible no matter how far below target they are. The window
   widens until it holds 3 weigh-in days, capped at 30.
6. **"Keep going" offers quick amounts** — 5 lb more / 10 lb more /
   Custom — because "another 5 lbs" is the actual thought.
7. **One re-arm at 14 days** if still at target and still undecided,
   then silence for that target.
8. **Milestones stay silent for now.** Build the one moment that
   matters, see it on device, generalize later if it earns it.

## Part A — the criterion (kit, pure)

New `GoalCompletion` in OnigiriKit:

```swift
public struct GoalCompletion: Equatable, Sendable {
    /// The window the budget itself plans from — preferred, not required.
    public static let preferredWindowDays = 7
    /// How far back the search may reach for a third weigh-in day.
    public static let maximumWindowDays = 30
    public static let minimumWeighInDays = 3

    public let targetLb: Double
    public let basisLb: Double?     // nil when 3 days can't be found
    public let weighInDays: Int
    /// False when the 7-day window sufficed; true when it had to reach
    /// further back. The UI can explain the number it's showing.
    public let usedWiderWindow: Bool

    public var isMet: Bool {
        weighInDays >= Self.minimumWeighInDays
            && (basisLb.map { $0 <= targetLb } ?? false)
    }

    public static func evaluate(
        targetLb: Double, history: [WeightTrend.Point],
        now: Date = .now, calendar: Calendar = .current
    ) -> GoalCompletion
}
```

**The widening rule** (decision 5): take the daily lows no older than
`maximumWindowDays`. If 3+ of them fall inside the preferred 7 days, use
those — a daily weigher's result is exactly the plan's basis. Otherwise
use **the most recent 3**, i.e. the SMALLEST window that contains three
weigh-in days. Fewer than 3 within 30 days ⇒ not met, `basisLb` nil:
nothing recent enough to trust.

Take exactly 3 when widening, not everything inside 30 days — "widen
until it has 3" is a different (and much wider) mean than "average the
last month", and the second would let a reading from four weeks ago drag
a current result around.

**Honest consequence, worth stating because Part A's whole pitch was
that the two agree:** in the WIDENED case the criterion is no longer the
number the budget plans from. A weekly weigher's celebration is judged
on their last 3 weigh-ins while the budget still plans from a 7-day
window that may hold only one. That divergence is the price of not
locking them out, and it is the better trade — but it means the Goal
screen must never present the criterion's basis AS the planning basis.
`usedWiderWindow` exists so a later "over your last 3 weigh-ins" caption
can say which is which.

Built on `WeightTrend.dailyLows`, which already collapses each day to
its LOWEST reading — so the evening-weigh-in problem (2–3 lb high) is
solved before the criterion sees it, and `count` is a count of weigh-in
DAYS rather than of samples. Two weigh-ins in one morning can't buy a
day toward the guard.

**Extract the window, don't re-type it.** `WeightTrend.targetBasisLb`
already filters `> cutoff && <= now` over the daily lows and means them.
`evaluate` needs the same points AND their count, so factor the filter
into one `WeightTrend.recentDailyLows(_:windowDays:now:calendar:)` and
build BOTH on it. Two copies of a window boundary is exactly the drift
that makes a celebration and a budget disagree — which is the bug this
part exists to fix.

**Deliberately independent of the `WeightBasis` setting.** Someone
planning from `.lastWeighIn` still gets the smoothed criterion: a
milestone should describe the body, not the planning knob, and a
criterion that changed with a settings toggle would let one user's
"reached" be another's "not yet" on identical scale data.

`basisLb` and `weighInDays` are public because the Goal screen can then
say WHY it isn't met yet ("2 more weigh-in days", "0.4 lb to go")
without recomputing anything. Not built in this pass — the affordance
just shouldn't need a new type later.

## Part B — the Today card

Shown on Today when: mode is `lose`, a target exists, `isMet`, and the
acknowledgement key (below) doesn't already name this target.

    ╭───────────────────────────╮
    │ 🍙 You hit your target   ✕│
    │ 22 lb down · Choose what's │
    │ next in Goal ›            │
    ╰───────────────────────────╯

- Badge is the CONFIGURED reward emoji (`SharedStore.rewardIconKey`,
  default 🍙), not a hardcoded glyph — same badge the streak already
  awards, so the celebration looks like the app's own reward.
- "22 lb down" comes from `GoalProgress.lostLb`; the "since <date>"
  form is already solved there, including the derived-start case.
- Placement: directly under Today's headline block and ABOVE the Daily
  Goal card — it is about the goal, and it must not displace the
  kcal-left headline.
- Tap → `QuickActions.shared.goalRequest = true`, the route Today's
  Daily Goal card already uses (`TodayView.swift:563` →
  `ContentView.swift:148`). No new navigation machinery.
- ✕ dismisses by writing the acknowledgement key. Nothing is lost: the
  Goal section keeps the state and the choices.

### The acknowledgement keys

Three app-group keys, because decision 7 needs a "once more, later":

- `goalReachedAckTarget` (Double, 0/absent = none) — WHICH target was
  acknowledged.
- `goalReachedAckAt` (Date) — when it was last dismissed.
- `goalReachedAckCount` (Int) — how many times it has been dismissed for
  that target.

Show the card iff `isMet`, mode is `lose`, and either:

- `ackTarget != goal.targetWeightLb` (never acknowledged for this
  target), or
- `ackCount == 1` and `now >= ackAt + 14 days` — the single re-arm.

`ackCount >= 2` is silence for that target, forever. Dismissing
increments the count and stamps the date; choosing Maintain or saving a
new target sets it to 2 outright — a decision is not a dismissal, and it
must not leave a re-arm loaded.

Storing the TARGET rather than a Bool is what makes the rest fall out
for free: bouncing above and back below the SAME target never
re-celebrates, and a NEW target re-arms the card automatically for when
that one is met.

The re-arm is not a nag for its own sake — the undecided state grades
days more permissively than either real mode (see Current state), and
that drift is otherwise invisible forever.

Do NOT add these to `WatchSync`'s key list or `PreferenceSnapshot`: the
watch has no Goal editor and shows no card, and syncing them would make
a dismissal on one device silence a celebration that never happened on
the other.

## Part C — the Goal section

Replace the single-button block at `GoalView.swift:570`:

    🍙 You've reached your target — nice work.
       22 lb down since Mar 4.
    [ Keep going — set a new target ]
    [ Switch to Maintain ]

- The existing sentence stays VERBATIM — it is already the user's copy;
  only the progress line and the second button are new.
- NOT gated by the acknowledgement key. The card is the announcement
  (dismissible, once); this is the state, and it stands until a choice
  is made. Dismissing the card must never hide the decision.
- `Switch to Maintain` keeps its current behavior (set mode, save) and
  additionally writes the acknowledgement key.
- `Keep going` offers quick amounts (decision 6) — the common intent in
  one tap, with Custom for everything else:

      Keep going — lose more
        [ 5 lb more ]  [ 10 lb more ]  [ Custom… ]

  - An amount is measured from the TARGET you just hit, not from
    today's weight: hitting 175 and tapping "5 lb more" sets **170**, a
    round number, rather than 169.6 off a basis that moves daily.
  - Chips render in the DISPLAY unit with round values for that unit —
    5/10 lb, 2/5 kg — and convert to canonical lb on save
    (`WeightUnit`, the storage rule). "2.3 kg more" is not a chip.
  - Each chip sets the target AND the suggested date (Part E) in one
    tap, then saves through the same `GoalUpsert` path as Custom.
  - `Custom…` focuses the Target field with no number pre-filled: past
    the two common cases, the app should not appear to pick your goal.

## Part D — continuing keeps the start

Add a case to `GoalUpsert.StartChange`:

```swift
/// Continuing past a reached target: the same journey, extended. Leaves
/// the stored start alone AND suppresses the target-changed re-stamp.
case keep
```

- Only the continue-flow passes `.keep`. Editing a target by hand
  anywhere else keeps today's re-stamp — a new target IS a new journey
  unless you arrived at it by finishing the last one.
- Consequence, and the point: `GoalProgress.milestones` keep counting
  from the original start, so the ladder EXTENDS (25 lb down, 30 lb
  down…) instead of restarting at "5 lb down". The bar reads 22 of 27.
- A goal with no stored start (pre-feature, derived from the earliest
  weigh-in) keeps deriving — `.keep` leaves nil alone, which is correct.
- A manual start (`startIsManual`) is already sticky and is unaffected.

## Part E — the date trap

`requiredDailyDeficit` divides by `max(1, daysRemaining)`. A fresh
target against a stale stored date is therefore catastrophic: 5 lb with
1 day left is **17,500 kcal/day**, and nothing clamps it.

- The continue-flow must move the date. Default the picker to
  `today + max(14, poundsToLose × 7)` — 1 lb/week, floored at two weeks
  — and let the user change it freely. Taste knob; the floor is there so
  a 1 lb goal doesn't propose a 7-day sprint.
- No new warning needed: `plan.isAggressive` is ALREADY surfaced on Goal
  (`GoalView.swift:260`), Today, and onboarding. The date default just
  stops the common path from tripping it.

## What does not change

The zero-deficit behavior at target (budget = full burn) — that stays
the honest answer for someone who hasn't decided yet. `DayBudget`,
badge rules, `DeficitTargetHistory` stamping, widgets, and the watch are
all untouched. The celebration changes what the app SAYS at target, not
what it computes.

## Risks / edges

- **The criterion can un-meet itself.** The basis rises, `isMet` goes
  false, and the Goal section's celebration disappears while the ack key
  still names that target. Correct (you're no longer at target) but it
  means the card can't come back for that target even if the basis dips
  again — accepted, and it's the anti-nag behavior.
- **Maintenance mode has no target to compare**; every surface here is
  gated on `mode == lose`. A maintenance "target" is a hold-near anchor,
  and `GoalUpsert` already refuses to stamp journeys for it.
- **A target above current weight** (someone editing downward past
  themselves) is already blocked by `validate` → `.targetNotBelowCurrent`.
- Sparse history: with fewer than 3 weigh-in days in the window, `isMet`
  is false no matter how low the readings are. Intended, and the reason
  `weighInDays` is exposed so the UI can say so later.

## Tests

Kit (`GoalCompletionTests`), the cases that define the rule:
- basis at/below target with 3+ weigh-in days in 7 → met; the same
  readings with only 2 available → widens (below).
- one low reading in an otherwise-high week → not met (basis, not min).
- exactly at target → met (`<=`).
- two readings the same day count as ONE day, and the LOW one wins
  (a 176.0 evening + 174.0 morning is a 174.0 day).
- a reading exactly `preferredWindowDays` old is excluded — pin the
  boundary, since Part A moves it into shared code.
- **widening**: a weekly weigher with 3 readings spanning ~21 days, all
  below target → met, `usedWiderWindow == true`; the mean is of those
  THREE, not of everything within 30 days (seed a 4th at day 26 that
  would change the mean if wrongly included).
- **the cap**: 3 readings whose oldest is 31 days back → not met.
- a daily weigher's result is identical with and without the widening
  code path (`usedWiderWindow == false`) — the refactor must not move
  the common case.
- empty history / all readings older than the cap → not met, no crash.
- `WeightTrend.targetBasisLb` keeps its existing results after being
  re-pointed at the shared window (guard against the refactor).

Ack-key logic is worth its own pure helper + tests rather than living in
the view — the re-arm is a small state machine and "shows twice, never
three times" is exactly the rule that rots silently:
- never dismissed → shows.
- dismissed today → hidden; at +13 days hidden; at +14 days shows again.
- dismissed twice → never shows for that target, at any age.
- decision taken (Maintain / new target) → never shows, even at +14.
- a NEW target with the old keys still stored → shows.

UI (opt-in, seeded — the seeder writes body mass): weights below target
across 3+ days ⇒ the Today card appears; ✕ hides it and it stays hidden
across a relaunch; the Goal section offers both buttons; choosing
"Keep going" with a new target leaves `Progress` reading the ORIGINAL
start rather than 0%.

## Files

- `Packages/OnigiriKit/Sources/OnigiriKit/GoalCompletion.swift` (new)
  and `WeightTrend.swift` (extract `recentDailyLows`), + kit tests.
- `LibraryModels.swift` — the `goalReachedAckTarget` key.
- `Onigiri/Views/TodayView.swift` — the card.
- `Onigiri/Views/GoalView.swift` — criterion swap + the two-button
  section.
- `Onigiri/Models/GoalUpsert.swift` — `StartChange.keep`.
- `OnigiriUITests/OnigiriUITests.swift` — the opt-in flow above.

## Deliberately NOT in this pass

- **Milestone celebrations** (decision 8). `GoalProgress.Milestone`
  already carries `isReached` and nothing marks it, and the card
  machinery would generalize almost as-is — the ack key would store a
  milestone instead of a target. Held back until the target moment has
  been seen on device, because the failure mode of celebrating
  everything is that nothing reads as a celebration.
- **Regain after Maintain.** Nothing watches for drifting back up above
  a held anchor. It's the natural next question and a different feature
  (it needs a tolerance band and a much more careful tone).

## Open (taste knobs, decide on device)

1. The date default's shape (1 lb/week, 2-week floor).
2. Whether the Goal section should say why it ISN'T met yet ("2 more
   weigh-in days") — the data is already in `GoalCompletion`, and
   `usedWiderWindow` can caption which readings it used.
3. Card placement above vs below the Daily Goal card.
4. Chip amounts per unit (5/10 lb, 2/5 kg).
