import Foundation

/// A local notification the app should have pending.
public struct PlannedReminder: Sendable, Equatable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable {
        case meals, water, streak
    }

    public let kind: Kind
    public let fireDate: Date
    public let title: String
    public let body: String

    public var id: String {
        "onigiri.reminder.\(kind.rawValue).\(Int(fireDate.timeIntervalSince1970))"
    }
}

/// Decides which reminder notifications should exist right now.
///
/// There is no background execution (free team, no push): notifications are
/// pre-scheduled from the state known at planning time, and the app replans
/// — replacing everything pending — on every foreground and after every log.
/// So: plan only what current state still calls for; "cancelling" a stale
/// reminder is just replanning without it. Future days' state is unknowable,
/// which is why they only get the state-free meal nudge.
public enum ReminderPlanner {
    public struct DayState: Sendable, Equatable {
        public var hasLoggedFood: Bool
        public var waterOz: Double
        public var waterGoalOz: Double
        /// Current streak; an unfinished today doesn't break it, and an
        /// earned today counts (StreakCalendar semantics).
        public var streak: Int
        public var todayGoalMet: Bool

        public init(
            hasLoggedFood: Bool = false,
            waterOz: Double = 0,
            waterGoalOz: Double = 64,
            streak: Int = 0,
            todayGoalMet: Bool = false
        ) {
            self.hasLoggedFood = hasLoggedFood
            self.waterOz = waterOz
            self.waterGoalOz = waterGoalOz
            self.streak = streak
            self.todayGoalMet = todayGoalMet
        }
    }

    public struct Enabled: Sendable, Equatable {
        public var meals: Bool
        public var water: Bool
        public var streak: Bool

        public init(meals: Bool = false, water: Bool = false, streak: Bool = false) {
            self.meals = meals
            self.water = water
            self.streak = streak
        }

        public var any: Bool { meals || water || streak }
    }

    /// User-tunable check-in times, minutes since midnight. Defaults are
    /// the original fixed schedule; Settings writes the SharedStore keys
    /// and the scheduler passes `SharedStore.reminderTimes` through.
    public struct Times: Sendable, Equatable {
        public var mealMinute: Int
        public var streakMinute: Int
        /// The water check-ins. Pacing expectations attach in
        /// CHRONOLOGICAL order — the earliest check-in always expects
        /// the least — and same-time duplicates collapse, with the
        /// expectations re-paced evenly over what remains (N distinct
        /// times expect 1/N, 2/N, … of the goal).
        public var waterMinutes: [Int]

        public init(
            mealMinute: Int = 14 * 60,
            streakMinute: Int = 20 * 60,
            waterMinutes: [Int] = [11 * 60, 15 * 60, 19 * 60]
        ) {
            self.mealMinute = mealMinute
            self.streakMinute = streakMinute
            self.waterMinutes = waterMinutes
        }
    }

    /// Days of meal nudges kept pending so they still fire when the app
    /// hasn't been opened; a replan on any launch extends the window.
    static let horizonDays = 3

    public static func plan(
        state: DayState,
        enabled: Enabled,
        times: Times = Times(),
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []
        let todayStart = calendar.startOfDay(for: now)
        func at(minute: Int, dayOffset: Int) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: todayStart)
            else { return nil }
            let clamped = min(max(0, minute), 24 * 60 - 1)
            return calendar.date(
                bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: day
            )
        }

        if enabled.meals, !state.hasLoggedFood,
           let fire = at(minute: times.mealMinute, dayOffset: 0), fire > now {
            planned.append(mealNudge(at: fire))
        }
        if enabled.water, state.waterGoalOz > 0, state.waterOz < state.waterGoalOz {
            let checkpoints = Set(times.waterMinutes).sorted()
            for (index, minute) in checkpoints.enumerated() {
                let expectedShare = Double(index + 1) / Double(checkpoints.count)
                guard let fire = at(minute: minute, dayOffset: 0), fire > now,
                      state.waterOz < state.waterGoalOz * expectedShare
                else { continue }
                planned.append(PlannedReminder(
                    kind: .water, fireDate: fire,
                    title: "Water check-in",
                    body: "You're at \(Int(state.waterOz)) of \(Int(state.waterGoalOz)) oz."
                ))
            }
        }
        if enabled.streak, !state.todayGoalMet, state.streak >= 2,
           let fire = at(minute: times.streakMinute, dayOffset: 0), fire > now {
            planned.append(streakWarning(at: fire, streak: state.streak))
        }
        // Tomorrow's streak warning is safe to pre-plan only when today is
        // already earned — otherwise the streak may be dead by then. By
        // the time it fires, the earned today has JOINED the streak:
        // say N+1, not today's N.
        if enabled.streak, state.todayGoalMet, state.streak >= 2,
           let fire = at(minute: times.streakMinute, dayOffset: 1) {
            planned.append(streakWarning(at: fire, streak: state.streak + 1))
        }
        if enabled.meals {
            for day in 1...horizonDays {
                if let fire = at(minute: times.mealMinute, dayOffset: day) {
                    planned.append(mealNudge(at: fire))
                }
            }
        }
        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    private static func mealNudge(at fire: Date) -> PlannedReminder {
        PlannedReminder(
            kind: .meals, fireDate: fire,
            title: "Nothing logged yet",
            body: "Log your meals to keep today's balance up to date."
        )
    }

    private static func streakWarning(at fire: Date, streak: Int) -> PlannedReminder {
        PlannedReminder(
            kind: .streak, fireDate: fire,
            title: "Keep your streak going",
            body: "Your \(streak)-day streak ends at midnight — log your day."
        )
    }
}
