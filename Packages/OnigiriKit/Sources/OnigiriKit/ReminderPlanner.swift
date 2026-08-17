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
        /// Only ever compared against zero — the water nudge asks
        /// "anything logged?", not "how far along?". The goal it used to
        /// be paced against is deliberately absent.
        public var waterOz: Double
        /// Current streak; an unfinished today doesn't break it, and an
        /// earned today counts (StreakCalendar semantics).
        public var streak: Int
        public var todayGoalMet: Bool

        public init(
            hasLoggedFood: Bool = false,
            waterOz: Double = 0,
            streak: Int = 0,
            todayGoalMet: Bool = false
        ) {
            self.hasLoggedFood = hasLoggedFood
            self.waterOz = waterOz
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
        /// The water check-ins. Same-time duplicates collapse; the
        /// pacing expectations that used to attach to them in
        /// chronological order are gone with the pacing gate itself.
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
        // Gated on "nothing logged", NOT on pace (the user, 2026-08-17 —
        // `plans/PLAN-reminders.md`). A pacing claim is falsified by any
        // log in the gap between planning and firing; "you haven't logged
        // any water" is falsified only by a log in that same gap AND is
        // the one thing a reminder can say that stays true all day on the
        // days it is for. The pacing shares it replaces put a live figure
        // in the body, which is what read "0 of 64 oz" after a morning of
        // watch-logged water.
        if enabled.water, state.waterOz == 0 {
            for minute in Set(times.waterMinutes).sorted() {
                guard let fire = at(minute: minute, dayOffset: 0), fire > now
                else { continue }
                planned.append(waterNudge(at: fire))
            }
        }
        // Gated on LOGGING, not on the goal: todayGoalMet judges with
        // burn-so-far, and the day's remaining resting burn arrives
        // between the 8 PM check and midnight — so a fully logged,
        // on-track day read "unmet" and the warning fired every evening
        // (the user, 2026-07-22). The warning is "you forgot to log",
        // matching its own copy; goal math stays out of it.
        if enabled.streak, !state.hasLoggedFood, state.streak >= 2,
           let fire = at(minute: times.streakMinute, dayOffset: 0), fire > now {
            planned.append(streakWarning(at: fire))
        }
        // Tomorrow's streak warning is safe to pre-plan only when today is
        // already earned — otherwise the streak may be dead by then. It
        // used to have to say N+1 rather than today's N, because the body
        // printed the count; with the count gone the two warnings are the
        // same sentence and the arithmetic went with it.
        if enabled.streak, state.todayGoalMet, state.streak >= 2,
           let fire = at(minute: times.streakMinute, dayOffset: 1) {
            planned.append(streakWarning(at: fire))
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

    private static func waterNudge(at fire: Date) -> PlannedReminder {
        PlannedReminder(
            kind: .water, fireDate: fire,
            title: "Water check-in",
            body: "Time for a glass of water."
        )
    }

    /// No day count: the number is decided at planning time and the
    /// warning fires hours later, so a streak that ends in between made
    /// the body a lie. Nothing here can be falsified by the clock.
    private static func streakWarning(at fire: Date) -> PlannedReminder {
        PlannedReminder(
            kind: .streak, fireDate: fire,
            title: "Keep your streak going",
            body: "Your streak ends at midnight — log your day."
        )
    }
}
