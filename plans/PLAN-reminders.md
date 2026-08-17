# PLAN — Reminder freshness

**Symptom (the user, 2026-08-17):** 24 oz of water logged in the morning on
the WATCH; the 11 AM water check-in still read **"You're at 0 of 64 oz."**

**Verdict:** not a new bug, and not fixable by fixing what broke. A
pre-scheduled `UNNotificationRequest` carries text written hours before it
fires, and on a free personal team there is no push and no reliable
background execution to rewrite it. Every freshness mechanism the app has
is best-effort. The copy has to stop depending on them.

**This already happened once.** `OnigiriApp.swift` carries the note:
*"the 11 AM water check-in read '0 of 72 oz' after a morning of
watch-logged water (2026-07-16)"*. The fix then was to replan from the
HealthKit observer's background wake. That was the right mechanism and it
still could not hold — see §2.

---

## 1. How a reminder's text is decided

`ReminderPlanner.plan` runs over a `DayState` snapshot and returns
`PlannedReminder`s with `title` and `body` already rendered
(`ReminderPlanner.swift:127`):

```swift
body: "You're at \(waterUnit.value(fromOz: state.waterOz)) of \(waterUnit.text(fromOz: state.waterGoalOz))."
```

`ReminderScheduler.replanNow` copies that into `UNMutableNotificationContent`
and hands it to `UNCalendarNotificationTrigger`. From that moment the text
is immutable. iOS delivers exactly what was written, whenever the trigger
comes due.

The same snapshot decides **whether** each reminder exists at all — water
on `state.waterOz < goal * expectedShare`, the meal nudge and the streak
warning on `!state.hasLoggedFood`. So a stale snapshot produces both a
wrong number *and* a reminder that should not have fired.

Water is simply the only kind that prints a live figure, so it is the one
that visibly lies. The other two fail identically and silently: log dinner
at 7 PM without a replan and the 8 PM warning still says *"Your 3-day
streak ends at midnight — log your day."*

## 2. Why the replans lose

Three things call `replan`, and none covers a watch log promptly:

| Trigger | Site | Covers a watch log? |
|---|---|---|
| Foreground | `ContentView.swift:133` | Only if you open the app before it fires |
| After an in-app log | `Feedback.swift:335` (`didMutate`) | No — the write happened elsewhere |
| HealthKit observer wake | `OnigiriApp.swift:73` | In principle; see below |

The observer is the only automatic path, and it has two problems:

- **watchOS caps its own background delivery at roughly hourly**, already
  noted at `HealthKitService.swift:135`. A 7 AM watch log may not reach the
  phone's store before an 11 AM check-in.
- **There is no watch → phone channel at all.** WatchConnectivity runs one
  way here: `PhoneSyncService.swift:260` calls `updateApplicationContext`
  phone → watch, and `WatchSyncReceiver.swift:127` receives it. Nothing
  goes back. The watch cannot tell the phone it logged anything; HealthKit
  sync is the only carrier.

A fourth gap is unrelated to the watch and worth fixing regardless:
**`LogWaterIntent` never replans.** `SharedIntents/LogWaterIntent.swift:38`
writes to HealthKit and returns. Siri, Shortcuts, the widget button and
Control Center all run through it, and all of them lean entirely on the
observer catching the write second-hand.

## 3. The rule this yields

> **A notification may not assert anything that can change between being
> scheduled and being delivered.**

Everything below follows from it. The point is not to make the mechanisms
better — they cannot be made reliable without push — but to make their
failure harmless.

## 4. Layers

### Layer 1 — No live numbers in any body (decided with the user, 2026-08-17)

`"You're at 0 of 64 oz."` is falsifiable and was falsified. Remove the
progress figure; remove the streak's day count too, for the same reason.
What remains is a nudge, which cannot be contradicted by the clock:

| Kind | Now | After |
|---|---|---|
| Water | `You're at 0 of 64 oz.` | *(nudge, no figure)* |
| Streak | `Your 3-day streak ends at midnight — log your day.` | `Your streak ends at midnight — log your day.` |
| Meals | `Log your meals to keep today's balance up to date.` | unchanged — already carries nothing |

The DEBUG preview samples (`ReminderScheduler.swift:180`) hardcode `12` and
`64` and must move with the real strings, or the preview stops resembling
what ships.

### Layer 2 — Water fires only when nothing is logged (decided, 2026-08-17)

Replace the pacing gate with `state.waterOz == 0`. The claim "you haven't
logged any water" is binary, and it is the claim least likely to have gone
stale — it breaks only if you logged in the gap, where a pacing claim
breaks on any log at all.

This deletes `expectedShare` and with it the chronological re-pacing of the
check-in times. The three time rows stay: on a genuinely dry day, three
spread nudges are three chances to notice, and on any other day none of
them fires.

Accepted cost, stated plainly: log 8 oz at breakfast and stop, and the app
will not nudge you again that day. That is the trade for never being wrong.

### Layer 3 — Close the replan gaps (mechanism, best-effort by nature)

**`LogWaterIntent` needed no change — corrected on inspection.**
`startObservingLogChanges` registers with `predicate: nil` from
`OnigiriApp.init`, so it observes *any* `dietaryWater` write including the
app's own process's. Every in-process intent run therefore already
replans, and adding a call would have been redundant code that also
cannot compile: `SharedIntents/` builds into the widget and watch targets,
which have no `ReminderScheduler`.

**Watch → phone `transferUserInfo` on log — BUILT.** The one mechanism
that would have prevented the reported symptom. `WatchSync.watchLogNotice‑
Key` carries it; `WatchSyncReceiver.notifyPhoneOfLog()` sends from all
four watch write paths (water, meal, edit, delete); `PhoneSyncService`'s
`didReceiveUserInfo` replans and reloads widgets. Chosen over
`sendMessage` because it queues, survives the phone app not running, and
*wakes the phone in the background* to receive. The arrival is the signal
— the timestamp only keeps successive transfers distinct — and the replan
re-queries Health, so a wake that beats the sample costs one wasted
replan and nothing worse.

Layer 3 is explicitly **not** load-bearing. Layers 1 and 2 must stand on
their own, because a queued transfer still arrives whenever it arrives.

### Layer 4 — Customization

Deliberately **not** built. The user's instruction was "don't overcomplicate
it", and Layer 2 answers the underlying want without a new control. Revisit
only if the accepted cost above turns out to bite.

## 5. Settings copy that moved with it

`Water pacing` named the mechanism that was deleted. Each toggle on the
Reminders screen now names its own CONDITION, which is also the whole
explanation of when it fires:

- `Not logged by 2:00 PM` (unchanged)
- `Water pacing` → **`No water logged`**
- `Streak about to lapse` (unchanged)

Footer: *"Water check-ins only fire on days with nothing logged. The
streak check warns before midnight."*

## 6. Status and what to verify

Layers 1, 2 and 3 BUILT 2026-08-17. Layer 4 deliberately not built.
576 kit tests pass; `ReminderPlannerTests` is 16 tests including
`anyWaterAtAllSilencesTheDay` (the reported case) and
`noReminderBodyCarriesALiveFigure` (scans every planned title and body
for a digit — the cheapest possible guard against Layer 1 regressing).

A green build proves nothing about the parts that matter, because the
failure is a timing one:

- **Log water on the WATCH in the morning, leave the phone alone**, and
  confirm the check-in does not fire. This is the actual regression test
  and no simulator can run it — the iPhone and Watch sims share a Health
  store, so a watch-side write is indistinguishable from a phone one.
- Confirm the DEBUG preview still matches the shipping copy (verified on
  the 26.5 sim, 2026-08-17: *"Water check-in / Time for a glass of
  water."*).
- If the notice ever seems not to arrive, check that
  `didReceiveUserInfo` is reached at all before suspecting the planner —
  `WCSession` delivers nothing while the watch app has never launched.
