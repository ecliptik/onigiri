import Foundation

/// Pure math for turning a weight-loss goal into a daily calorie budget.
public enum CalorieBudget {
    /// Approximate energy content of one pound of body fat.
    public static let kcalPerPound: Double = 3500

    /// Daily deficits beyond this are flagged as unsustainable.
    public static let maxSafeDailyDeficit: Double = 1000

    /// Daily budgets below this are flagged as too aggressive.
    ///
    /// A FLOOR under the floor: the real red line is the body's own
    /// resting energy, which this flat number cannot see. It is the same
    /// 1,500 for every body, while `BasalEstimate.restingKcal` — which
    /// the app already computes for the budget's resting credit — is
    /// specific to this one. For the seeder's reference body (178 cm,
    /// 40 years, ~200 lb) resting is ~1,742, so a 1,600 kcal budget
    /// passed this guardrail silently while sitting 142 kcal UNDER the
    /// body's baseline — and that budget is reachable, not pathological:
    /// an 800 kcal/day deficit against a 2,400 kcal burn (2026-08-16).
    ///
    /// Kept rather than replaced, because the resting estimate is nil
    /// whenever Health can't describe the body (see `BasalEstimate`), and
    /// a guardrail that disappears with its input is not a guardrail.
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
            // A budget is what there is left to EAT, and that has a
            // floor at nothing. Unfloored it went NEGATIVE the moment a
            // goal asked for more than the day burns: a target moved
            // 210 → 200 against a stale date wanted 2,453 kcal/day out
            // of a 1,956 kcal burn, so the budget came to −497 and
            // Today read "+498 kcal over" at 9am with nothing logged
            // (the user, 2026-08-18). Nobody has overeaten before their
            // first meal; the goal was unreachable, which is a
            // different sentence and `isAggressive` is the one that
            // says it.
            //
            // The guardrails that would have caught this — the flat
            // `minReasonableBudget` and the body's own resting floor —
            // live in `plan()`, which is the Goal-tab PREVIEW. This is
            // the function every real day is judged by and it carried
            // none of them.
            dailyBudget: max(0, dayBurnKcal - deficit),
            // A past day can't be talked out of what it already was.
            // This flag means specifically "move your target date",
            // which a spent day cannot act on — so it stays false even
            // when the floor above bit. A caller that needs to know the
            // goal outran the burn reads the two numbers instead
            // (`requiredDailyDeficit > 0 && dailyBudget == 0`), which
            // says that and only that, on any day.
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
        restingFloorKcal: Double? = nil,
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
            averageDailyBurn: burn,
            restingFloorKcal: restingFloorKcal
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
        bandLb: Double = GoalFinishLine.bandLb,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Double? {
        guard let current = currentWeightLb, let target = targetWeightLb, let targetDate
        else { return nil }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: targetDate
        ).day ?? 0
        return requiredDailyDeficit(
            currentWeightLb: current, targetWeightLb: target,
            daysRemaining: days, bandLb: bandLb
        )
    }

    /// Inside `bandLb` of the target the deficit is 0 — see
    /// `GoalFinishLine.bandLb` for why. The band lives HERE rather than
    /// in the UI so every surface that quotes a deficit agrees: Today,
    /// the widget, the watch, and the snapshots `DeficitTargetHistory`
    /// stamps for past days all come through this one function.
    public static func requiredDailyDeficit(
        currentWeightLb: Double, targetWeightLb: Double, daysRemaining: Int,
        bandLb: Double = GoalFinishLine.bandLb
    ) -> Double {
        let remaining = currentWeightLb - targetWeightLb
        guard remaining >= bandLb else { return 0 }
        return remaining * kcalPerPound / Double(max(1, daysRemaining))
    }

    /// `restingFloorKcal` is `BasalEstimate.restingKcal` — the body's own
    /// baseline, nil when Health can't describe it well enough to guess.
    /// nil reproduces the pre-2026-08-16 behaviour exactly: the flat
    /// `minReasonableBudget` alone.
    public static func plan(
        currentWeightLb: Double,
        targetWeightLb: Double,
        daysRemaining: Int,
        averageDailyBurn: Double,
        restingFloorKcal: Double? = nil
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
            // The greater of the two floors — see `minReasonableBudget`
            // for why both exist rather than one replacing the other.
            isAggressive: deficit > maxSafeDailyDeficit
                || budget < max(minReasonableBudget, restingFloorKcal ?? 0)
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
    /// `over` asks callers to render the number with an explicit "+".
    /// The caption is what tells 36-left from 36-over, and the caption
    /// is the first thing a complication drops — "36" on a watch face
    /// reads as 36 calories still available (the user, 2026-08-02). The
    /// sign travels with the value so no surface can show one without
    /// the other.
    static func remainingHeadline(
        _ remaining: Double
    ) -> (value: Double, caption: String, over: Bool) {
        remaining >= 0
            ? (remaining, "kcal left", false)
            : (-remaining, "kcal over", true)
    }
}
