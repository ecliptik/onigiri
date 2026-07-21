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
        max(averageKcal ?? 0, todayActualKcal, 2000)
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

    public static func plan(
        currentWeightLb: Double,
        targetWeightLb: Double,
        daysRemaining: Int,
        averageDailyBurn: Double
    ) -> Plan {
        let remainingLb = max(0, currentWeightLb - targetWeightLb)
        let days = Double(max(1, daysRemaining))
        let deficit = remainingLb * kcalPerPound / days
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
    static func remainingHeadline(_ remaining: Double) -> (value: Double, caption: String) {
        remaining >= 0 ? (remaining, "kcal left") : (-remaining, "kcal over")
    }
}
