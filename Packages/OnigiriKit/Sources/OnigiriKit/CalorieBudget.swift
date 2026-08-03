import Foundation

/// Pure math for turning a weight-loss goal into a daily calorie budget.
public enum CalorieBudget {
    /// Approximate energy content of one pound of body fat.
    public static let kcalPerPound: Double = 3500

    /// Daily deficits beyond this are flagged as unsustainable.
    public static let maxSafeDailyDeficit: Double = 1000

    /// Daily budgets below this are flagged as too aggressive.
    public static let minReasonableBudget: Double = 1500

    public struct Plan: Sendable, Equatable {
        /// Average calories/day that must be cut to hit the target on time.
        public let requiredDailyDeficit: Double
        /// Calories available to eat today: average burn minus required deficit.
        public let dailyBudget: Double
        /// True when the deficit or budget crosses the safety guardrails —
        /// the fix is a later target date, not eating less.
        public let isAggressive: Bool
    }

    /// Maintenance: eat what you burn. No deficit target — any deficit
    /// earns the badge (the goal-less rule) — but the budget, gauge,
    /// and kcal-left headline stay on screen.
    public static func maintenancePlan(averageDailyBurn: Double) -> Plan {
        Plan(requiredDailyDeficit: 0, dailyBudget: averageDailyBurn, isAggressive: false)
    }

    /// ANY day — today included — judged by what actually happened on it:
    /// the day's own burn (`DayBudget.dayBurn`: resting up front, active
    /// earned) against the deficit target in force that day.
    ///
    /// Deliberately not `derivePlan`: that one forecasts, flooring burn
    /// with the trailing average so an in-progress day doesn't read
    /// "over budget" at 9am. But the trailing average promises calories
    /// the day never goes on to earn — a finished day still quoted a burn
    /// that never happened ("67 kcal left" on a day that ended 29 over
    /// break-even, 2026-07-30), and an in-progress one kept the promise
    /// right up to bedtime ("695 kcal left" beside "197 kcal surplus",
    /// 2026-08-02). Crediting resting up front is what makes the forecast
    /// unnecessary: the predictable part of the day is already in hand at
    /// breakfast, so there is nothing left to guess at.
    public static func completedDayPlan(
        dayBurnKcal: Double, requiredDailyDeficit: Double
    ) -> Plan {
        let deficit = max(0, requiredDailyDeficit)
        return Plan(
            requiredDailyDeficit: deficit,
            dailyBudget: dayBurnKcal - deficit,
            // A past day can't be talked out of what it already was.
            isAggressive: false
        )
    }

    /// The burn a PROJECTION rides — the Goal tab's plan preview and
    /// onboarding's, where the question is "an average day", not
    /// "today". Your measured trailing average, with a 2000 kcal cold
    /// start until Health has any history to average.
    ///
    /// A SPECIFIC day's budget never comes from here — that is
    /// `DayBudget.dayBurn` fed to `completedDayPlan`. The Fixed budget
    /// style that used to substitute a pinned number for the average is
    /// gone with the setting: a budget that stays put no matter what you
    /// measure is the opposite of one you earn (2026-08-02).
    ///
    /// This used to be floored by today's own burn as well, so the Goal
    /// preview couldn't read lower than Today did on an active day. That
    /// floor made the figure neither one thing nor the other — an
    /// "average day" that moved with this afternoon's walk — and it
    /// still left the two screens 726 kcal apart at lunchtime with the
    /// same label on both (the user, 2026-08-02). Goal now shows BOTH
    /// numbers, each named, so this one is free to be a true average.
    public static func projectedDailyBurn(averageKcal: Double?) -> Double {
        max(averageKcal ?? 0, 2000)
    }

    /// The one shared answer to "what plan does this goal imply for an
    /// average day": maintenance eats what you burn; a weight goal
    /// spreads the remaining pounds over the days to the target date.
    /// nil when a weight goal lacks a current weight, target, or date.
    /// Both modes ride `projectedDailyBurn` — which is why this is the
    /// PREVIEW path, not the one any day is judged by.
    public static func derivePlan(
        isMaintenance: Bool,
        currentWeightLb: Double? = nil,
        targetWeightLb: Double? = nil,
        targetDate: Date? = nil,
        averageDailyBurnKcal: Double?,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Plan? {
        let burn = projectedDailyBurn(averageKcal: averageDailyBurnKcal)
        if isMaintenance { return maintenancePlan(averageDailyBurn: burn) }
        guard let current = currentWeightLb, let target = targetWeightLb, let targetDate
        else { return nil }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: targetDate
        ).day ?? 0
        return plan(
            currentWeightLb: current,
            targetWeightLb: target,
            daysRemaining: days,
            averageDailyBurn: burn
        )
    }

    /// The deficit the goal asks for, with no burn in it at all: pounds
    /// to lose, spread over the days left. Burn decides only what's left
    /// to EAT once the deficit is taken out, which is why the budget can
    /// ride the day's own burn (`completedDayPlan`) while the target it
    /// subtracts stays put. nil when the goal lacks a current weight, a
    /// target, or a date.
    public static func requiredDailyDeficit(
        currentWeightLb: Double?,
        targetWeightLb: Double?,
        targetDate: Date?,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Double? {
        guard let current = currentWeightLb, let target = targetWeightLb, let targetDate
        else { return nil }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: targetDate
        ).day ?? 0
        return requiredDailyDeficit(
            currentWeightLb: current, targetWeightLb: target, daysRemaining: days
        )
    }

    public static func requiredDailyDeficit(
        currentWeightLb: Double, targetWeightLb: Double, daysRemaining: Int
    ) -> Double {
        max(0, currentWeightLb - targetWeightLb) * kcalPerPound / Double(max(1, daysRemaining))
    }

    public static func plan(
        currentWeightLb: Double,
        targetWeightLb: Double,
        daysRemaining: Int,
        averageDailyBurn: Double
    ) -> Plan {
        let deficit = requiredDailyDeficit(
            currentWeightLb: currentWeightLb,
            targetWeightLb: targetWeightLb,
            daysRemaining: daysRemaining
        )
        let budget = averageDailyBurn - deficit
        return Plan(
            requiredDailyDeficit: deficit,
            dailyBudget: budget,
            isAggressive: deficit > maxSafeDailyDeficit || budget < minReasonableBudget
        )
    }
}

public extension CalorieBudget {
    /// Headline presentation for the remaining budget: a positive number
    /// with a caption, instead of a negative count.
    ///
    /// Bare "over" once read as "you gained" on a day that had banked a
    /// real deficit, just not the one the goal wanted (2026-07-30). The
    /// fix then was to call that case "kcal short", and it overcorrected
    /// twice over: short of WHAT was never said, and the number sat
    /// directly above a goal card reading "≈ 106 kcal over budget" — one
    /// figure, two words, one screen (the user, 2026-08-02).
    ///
    /// One caption, because there is only one quantity here —
    /// `budget − intake`. The severity split the two captions were
    /// reaching for can't live on this number anyway: a day 500 past its
    /// budget while only 100 past its BURN would have had its 500
    /// labelled "excess", which is a different figure entirely.
    /// Deficit-vs-excess belongs to Net, which subtracts the burn.
    ///
    /// "kcal over", not "kcal over budget": this renders in the ring, a
    /// complication and a widget flank, and three words is too many at a
    /// glance (the user, 2026-08-02). What it's over is answered on the
    /// goal card immediately below, which has the room to say it — so
    /// the short form reads as shorthand rather than as a second
    /// opinion, which is what "short" over "over budget" did.
    static func remainingHeadline(_ remaining: Double) -> (value: Double, caption: String) {
        remaining >= 0 ? (remaining, "kcal left") : (-remaining, "kcal over")
    }
}
