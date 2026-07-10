import Foundation
import UserNotifications
import OnigiriKit

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

    /// Call once at app start: the delegate is what lets a reminder banner
    /// while the app is frontmost (otherwise iOS swallows it silently).
    func activate() {
        UNUserNotificationCenter.current().delegate = self
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

    /// Recompute pending notifications from current state. Cheap enough to
    /// fire on every mutation; each call fully replaces the pending set.
    func replan() {
        Task { await replanNow() }
    }

    private func replanNow() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled.any else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        guard let state = await currentState() else { return }
        for reminder in ReminderPlanner.plan(state: state, enabled: enabled) {
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
    /// (StreakCalendar over dailyEnergyTotals with the plan's target).
    private func currentState() async -> ReminderPlanner.DayState? {
        let health = HealthKitService()
        async let entries = health.todayFoodEntries()
        async let totals = health.dailyEnergyTotals()
        let plan = await DailyPlanLoader.load(goal: WatchSync.loadGoal())
        guard let loadedEntries = try? await entries else { return nil }
        let earned = StreakCalendar.earnedDays(
            totals: (try? await totals) ?? [],
            targetDeficitKcal: plan.deficitTargetKcal
        )
        return ReminderPlanner.DayState(
            hasLoggedFood: !loadedEntries.isEmpty,
            waterOz: plan.summary.waterOz,
            waterGoalOz: SharedStore.waterGoalOz,
            streak: StreakCalendar.currentStreak(earned: earned),
            todayGoalMet: earned.contains(Calendar.current.startOfDay(for: .now))
        )
    }

    #if DEBUG
    /// Settings row: fire a sample of each reminder in a few seconds so
    /// on-device verification doesn't wait for 2 PM.
    func preview() {
        Task {
            guard await requestPermission() else { return }
            let center = UNUserNotificationCenter.current()
            let samples: [(PlannedReminder.Kind, String, String)] = [
                (.meals, "Nothing logged yet", "Log your meals to keep today's balance honest."),
                (.water, "Water check-in", "You're at 12 of 64 oz — time for water."),
                (.streak, "Streak on the line", "Your 3-day streak ends at midnight — log your day."),
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
        }
    }
    #endif

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
