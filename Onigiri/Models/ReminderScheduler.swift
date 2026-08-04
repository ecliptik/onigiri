import Foundation
import UserNotifications
import OnigiriKit
import os

// Logger is thread-safe; opt out of any MainActor default. Reminder taps
// are unobservable otherwise — nothing about a tap reaches any UI, so a
// tap that opens nothing and a tap that never arrives look identical
// from the outside (2026-08-04).
nonisolated(unsafe) let reminderLog =
    Logger(subsystem: "com.ecliptik.Onigiri", category: "reminders")

/// Schedules the ReminderPlanner's output as local notifications.
///
/// A free team has no push and no background refresh, so notifications are
/// pre-scheduled from the last-known state and the whole pending set is
/// replaced — on every foreground and after every log. Cancelling a stale
/// reminder is just replanning without it.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    private var enabled: ReminderPlanner.Enabled {
        let defaults = SharedStore.defaults
        return ReminderPlanner.Enabled(
            meals: defaults.bool(forKey: SharedStore.remindMealsKey),
            water: defaults.bool(forKey: SharedStore.remindWaterKey),
            streak: defaults.bool(forKey: SharedStore.remindStreakKey)
        )
    }

    /// The delegate is what lets a reminder banner show while the app is
    /// frontmost (otherwise iOS swallows it silently) AND what receives
    /// the tap — see `didReceive`, which routes the tap into the action
    /// the reminder nags about.
    ///
    /// Called from `AppDelegate.application(_:didFinishLaunchingWith‑
    /// Options:)`, NOT from a view: Apple requires the delegate to be
    /// assigned before the app finishes launching, and this used to ride
    /// `activate()` out of ContentView's `.task` — which runs once a view
    /// appears, well past that point. A notification tapped from a cold
    /// launch had no delegate to deliver its response to.
    func registerNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Call once the UI is up: replans from current state. The delegate
    /// registration above is deliberately separate and earlier.
    func activate() {
        registerNotificationDelegate()
        replan()
    }

    /// Ask for permission the moment the first toggle turns on — not at
    /// launch. Returns whether notifications are allowed.
    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        replan()
        return granted
    }

    /// Recompute pending notifications from current state; each call fully
    /// replaces the pending set. Pass `afterMutation: true` from log paths:
    /// a log can't move the deficit target (that's weight/goal/burn), so
    /// with reminders off those replans skip HealthKit entirely.
    func replan(afterMutation: Bool = false) {
        Task { await replanNow(afterMutation: afterMutation) }
    }

    /// Internal, awaitable: the HealthKit observer's background wake must
    /// finish the replan BEFORE the observer completion suspends the app.
    func replanNow(afterMutation: Bool) async {
        // Loading the plan stamps today's deficit-target snapshot (the
        // calendar judges history by it). Foreground replans always load —
        // a weigh-in may have synced in and moved today's target, and the
        // last stamp of the day is the one that stands. Mutation replans
        // with reminders off only load when today has no stamp yet.
        var plan: DailyPlanLoader.State?
        var goal: SyncedGoal?
        if enabled.any || !afterMutation || !DeficitTargetHistory.hasSnapshot(on: .now) {
            goal = WatchSync.loadGoal()
            plan = await DailyPlanLoader.load(goal: goal)
        }
        let center = UNUserNotificationCenter.current()
        // Only PLANNED reminders — the narrower "onigiri.reminder."
        // namespace, not "onigiri.", because the preview samples live
        // beside it and this sweep used to cancel them before their
        // few-second triggers could fire (tapping Preview did nothing).
        let pendingIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("onigiri.reminder.") }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        guard enabled.any, let plan else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        guard let state = await currentState(
            plan: plan, isMaintenance: goal?.isMaintenance ?? false
        ) else { return }
        for reminder in ReminderPlanner.plan(
            state: state, enabled: enabled, times: SharedStore.reminderTimes,
            waterUnit: SharedStore.waterUnit
        ) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.fireDate
            )
            try? await center.add(UNNotificationRequest(
                identifier: reminder.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }
    }

    /// Today's state, judged exactly like the Calendar tab judges days
    /// (StreakCalendar over dailyEnergyTotals with the plan's target,
    /// per-day snapshots, and the untracked threshold).
    private func currentState(
        plan: DailyPlanLoader.State, isMaintenance: Bool
    ) async -> ReminderPlanner.DayState? {
        let health = HealthKitService()
        let rule = DayBadgeRule.current(
            targetKcal: plan.deficitTargetKcal, isMaintenance: isMaintenance
        )
        async let entries = health.todayFoodEntries()
        async let totals = health.dailyEnergyTotals()
        guard let loadedEntries = try? await entries else { return nil }
        let earned = StreakCalendar.earnedDays(
            totals: (try? await totals) ?? [],
            fallbackRule: rule,
            rulesByDay: DeficitTargetHistory.rulesByDay(),
            untrackedBelowKcal: SharedStore.untrackedBelowKcal
        )
        // earnedDays excludes today by design (badges award only when
        // the day completes) — judge today live by the same rules, or
        // the 8 PM streak warning fires with the day already banked.
        // The day's OWN burn, the same figure earnedDays judges every
        // other day by. On raw measured burn this understates the
        // deficit by the whole un-accrued resting balance, so the 8 PM
        // warning could fire on a day already banked.
        let todayTotals = DayEnergyTotals(
            day: .now,
            intakeKcal: plan.summary.intakeKcal,
            burnKcal: plan.dayBurnKcal ?? plan.summary.totalBurnKcal
        )
        let todayGoalMet = StreakCalendar.isTracked(
            todayTotals, untrackedBelowKcal: SharedStore.untrackedBelowKcal
        ) && rule.met(deficitKcal: todayTotals.deficitKcal)
        return ReminderPlanner.DayState(
            hasLoggedFood: !loadedEntries.isEmpty,
            waterOz: plan.summary.waterOz,
            waterGoalOz: SharedStore.waterGoalOz,
            streak: StreakCalendar.currentStreak(earned: earned),
            todayGoalMet: todayGoalMet
        )
    }

    #if DEBUG
    /// Settings row: fire a sample of each reminder in a few seconds so
    /// on-device verification doesn't wait for 2 PM. Returns whether the
    /// samples were scheduled (false = notifications denied, the caller
    /// surfaces it). Deliberately NOT `requestPermission()`: its replan
    /// raced these very samples out of the pending set — and the sweep
    /// is namespaced away from "onigiri.preview." now too.
    func preview() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .denied:
            return false
        case .notDetermined:
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true
            else { return false }
        default:
            break
        }
        let samples: [(PlannedReminder.Kind, String, String)] = [
            (.meals, "Nothing logged yet", "Log your meals to keep today's balance up to date."),
            (.water, "Water check-in", "You're at \(SharedStore.waterUnit.value(fromOz: 12)) of \(SharedStore.waterUnit.text(fromOz: 64))."),
            (.streak, "Keep your streak going", "Your 3-day streak ends at midnight — log your day."),
        ]
        for (index, sample) in samples.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = sample.1
            content.body = sample.2
            content.sound = .default
            try? await center.add(UNNotificationRequest(
                identifier: "onigiri.preview.\(sample.0.rawValue)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(3 + index * 3), repeats: false
                )
            ))
        }
        return true
    }
    #endif

    // MARK: - UNUserNotificationCenterDelegate

    /// MainActor-isolated (inherited from the class), NOT `nonisolated`.
    ///
    /// These are `async` methods bridged to ObjC completion handlers, and
    /// the completion runs wherever the async function finishes. Marked
    /// `nonisolated` they finish on the cooperative pool, so UIKit's
    /// post-response work — `_updateSnapshotAndStateRestorationWith‑
    /// Action:windowScene:` — ran off the main thread, hit an
    /// NSAssertionHandler, and abort()ed the process ~235 ms into launch.
    /// Tapping any reminder flashed the screen and never opened the app
    /// (2026-08-04, crash `EXC_CRASH/SIGABRT` on thread
    /// `com.apple.root.user-initiated-qos.cooperative`). Never add
    /// `nonisolated` back to a UIKit-facing delegate callback.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Tapping a reminder routes into the action it nags about, like
    /// the app-icon quick actions for the same intents — it used to
    /// just open the app wherever it was left.
    /// MainActor-isolated — see `willPresent` above for why `nonisolated`
    /// here abort()ed the app on every reminder tap.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.identifier
        reminderLog.info("""
            tap id=\(id, privacy: .public) \
            action=\(response.actionIdentifier, privacy: .public)
            """)
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        // BOTH namespaces. Previews are `onigiri.preview.<kind>` while
        // planned reminders are `onigiri.reminder.<kind>.<firetime>`, and
        // matching only the latter meant tapping a preview ran this
        // handler and did NOTHING — i.e. the one on-demand way to test a
        // reminder tap was the one route that never worked (2026-08-04).
        let kind = PlannedReminder.Kind.allCases.first {
            id.hasPrefix("onigiri.reminder.\($0.rawValue).")
                || id == "onigiri.preview.\($0.rawValue)"
        }
        guard let kind else {
            reminderLog.error("tap matched no reminder kind: \(id, privacy: .public)")
            return
        }
        // Already on the main actor now, so no hop.
        switch kind {
        case .water:
            // Open Today (where water lives) — do NOT log. A reminder tap
            // used to log a serving outright, matching the logWater
            // shortcut and the Control Center button, and that asymmetry
            // was the problem: tapping a banner is also just how a
            // notification gets dismissed, so a half-awake tap wrote a
            // phantom 12 oz to Health and only a transient undo toast
            // stood between you and it (the user, 2026-08-04). The
            // shortcut, widget, and Siri paths still log immediately —
            // those are deliberate invocations, a nag is not.
            QuickActions.shared.dayRequest = .now
        case .meals, .streak:
            // Both ask "log something" — land in the Log sheet.
            QuickActions.shared.pending = .logMeal
        }
    }
}
