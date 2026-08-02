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

    /// The burn figure every plan derivation must use: the historical
    /// average, floored by today's actual burn and the 2000 kcal
    /// cold-start default. Once today's burn tops the average, the
    /// budget must follow or surfaces read "0 left"/"over" while
    /// reality has room (the 2.1.4 fix). Colocated here so Today, Goal,
    /// onboarding, the widgets, and the watch can't drift apart again.
    public static func expectedDailyBurn(
        averageKcal: Double?,
        todayActualKcal: Double = 0
    ) -> Double {
        // Budget style decides both halves: a pinned burn replaces the
        // trailing average, and Fixed stops today's own burn from raising
        // the budget (Goal tab, 2026-07-30). Defaults to the historical
        // behavior.
        let planned = SharedStore.planAverageBurn(measuredAverageKcal: averageKcal)
        let actual = SharedStore.budgetStyle.creditsActivity ? todayActualKcal : 0
        return max(planned ?? 0, actual, 2000)
    }

    /// The one shared answer to "what plan does this goal imply right
    /// now": maintenance eats what you burn; a weight goal spreads the
    /// remaining pounds over the days to the target date. nil when a
    /// weight goal lacks a current weight, target, or date. Both modes
    /// ride the `expectedDailyBurn` clamp.
    public static func derivePlan(
        isMaintenance: Bool,
        currentWeightLb: Double? = nil,
        targetWeightLb: Double? = nil,
        targetDate: Date? = nil,
        averageDailyBurnKcal: Double?,
        todayActualBurnKcal: Double = 0,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Plan? {
        let burn = expectedDailyBurn(
            averageKcal: averageDailyBurnKcal, todayActualKcal: todayActualBurnKcal
        )
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
    /// with a "kcal left"/"kcal over" caption, instead of a negative count.
    /// "Over" and "short" are different failures and were being told as
    /// one (the user, 2026-07-30): a day that ate 2,314 against 2,759
    /// burned said "246 kcal over", which reads as "you gained" when the
    /// day in fact banked a 445 kcal deficit — just not the 691 the goal
    /// wanted. Past the budget while still under your burn is SHORT of
    /// the goal; past your burn is genuinely OVER.
    static func remainingHeadline(
        _ remaining: Double, deficitKcal: Double = 0
    ) -> (value: Double, caption: String) {
        if remaining >= 0 { return (remaining, "kcal left") }
        return (-remaining, deficitKcal > 0 ? "kcal short" : "kcal over")
    }
}
