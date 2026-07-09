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

    /// Days to reach the target at the observed rate of loss (lb/day), or nil
    /// if the trend is flat or moving the wrong way.
    public static func projectedDaysToGoal(
        currentWeightLb: Double,
        targetWeightLb: Double,
        observedLossPerDayLb: Double
    ) -> Int? {
        let remainingLb = currentWeightLb - targetWeightLb
        guard remainingLb > 0 else { return 0 }
        guard observedLossPerDayLb > 0 else { return nil }
        return Int((remainingLb / observedLossPerDayLb).rounded(.up))
    }
}
