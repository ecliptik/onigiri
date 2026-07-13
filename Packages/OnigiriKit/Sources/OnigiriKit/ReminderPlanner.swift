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

    /// Fixed check-in times (Settings offers toggles, not time pickers).
    static let mealHour = 14
    /// Hour and the share of the water goal you'd expect by then.
    static let waterCheckpoints: [(hour: Int, expectedShare: Double)] = [
        (11, 1.0 / 3), (15, 2.0 / 3), (19, 1.0),
    ]
    static let streakHour = 20
    /// Days of meal nudges kept pending so they still fire when the app
    /// hasn't been opened; a replan on any launch extends the window.
    static let horizonDays = 3

    public static func plan(
        state: DayState,
        enabled: Enabled,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []
        let todayStart = calendar.startOfDay(for: now)
        func at(_ hour: Int, dayOffset: Int) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: todayStart)
            else { return nil }
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
        }

        if enabled.meals, !state.hasLoggedFood,
           let fire = at(mealHour, dayOffset: 0), fire > now {
            planned.append(mealNudge(at: fire))
        }
        if enabled.water, state.waterGoalOz > 0, state.waterOz < state.waterGoalOz {
            for checkpoint in waterCheckpoints {
                guard let fire = at(checkpoint.hour, dayOffset: 0), fire > now,
                      state.waterOz < state.waterGoalOz * checkpoint.expectedShare
                else { continue }
                planned.append(PlannedReminder(
                    kind: .water, fireDate: fire,
                    title: "Water check-in",
                    body: "You're at \(Int(state.waterOz)) of \(Int(state.waterGoalOz)) oz."
                ))
            }
        }
        if enabled.streak, !state.todayGoalMet, state.streak >= 2,
           let fire = at(streakHour, dayOffset: 0), fire > now {
            planned.append(streakWarning(at: fire, streak: state.streak))
        }
        // Tomorrow's streak warning is safe to pre-plan only when today is
        // already earned — otherwise the streak may be dead by then.
        if enabled.streak, state.todayGoalMet, state.streak >= 2,
           let fire = at(streakHour, dayOffset: 1) {
            planned.append(streakWarning(at: fire, streak: state.streak))
        }
        if enabled.meals {
            for day in 1...horizonDays {
                if let fire = at(mealHour, dayOffset: day) {
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
