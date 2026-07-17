import Foundation

/// The pure half of the Siri ask-back feature, unit-tested here:
/// numbers in, headline + caption + spoken sentence out. The AppIntent
/// wrapper lives in SharedIntents/ (compiled per-target — linkd rejects
/// SPM-delivered App Shortcuts); this stays in the kit so the grammar
/// and the over/under boundaries keep their tests. Mirrors the app's
/// own grammar (remainingHeadline's "kcal left"/"kcal over", the
/// hydration row's "X / Y oz").
public enum StatusPhrasing {
    public enum Metric: Sendable {
        case caloriesLeft
        case water
        case sodium
    }

    public struct Status: Sendable, Equatable {
        public let headline: String
        public let caption: String
        public let spoken: String
    }

    public static func phrase(
        metric: Metric,
        plan: DailyPlanLoader.State,
        waterGoalOz: Double,
        sodiumLimitMg: Double
    ) -> Status {
        switch metric {
        case .caloriesLeft:
            if let remaining = plan.remainingKcal {
                let headline = CalorieBudget.remainingHeadline(remaining)
                return Status(
                    headline: whole(headline.value),
                    caption: headline.caption,
                    spoken: remaining >= 0
                        ? "You have \(whole(remaining)) calories left today."
                        : "You're \(whole(-remaining)) calories over budget today."
                )
            }
            // No goal set: no budget to count down — report the balance.
            let summary = plan.summary
            return Status(
                headline: whole(summary.intakeKcal),
                caption: "kcal eaten",
                spoken: "You've eaten \(whole(summary.intakeKcal)) calories and burned "
                    + "\(whole(summary.totalBurnKcal)) today. Set a goal in Onigiri for a budget."
            )
        case .water:
            let oz = plan.summary.waterOz
            let met = oz >= waterGoalOz && waterGoalOz > 0
            return Status(
                headline: "\(whole(oz)) / \(whole(waterGoalOz)) oz",
                caption: "water",
                spoken: met
                    ? "Water goal met — \(whole(oz)) of \(whole(waterGoalOz)) ounces today."
                    : "You're at \(whole(oz)) of \(whole(waterGoalOz)) ounces of water today."
            )
        case .sodium:
            let mg = plan.summary.sodiumMg
            let over = sodiumLimitMg > 0 && mg > sodiumLimitMg
            return Status(
                headline: "\(whole(mg)) / \(whole(sodiumLimitMg)) mg",
                caption: over ? "sodium — over limit" : "sodium",
                spoken: over
                    ? "You're over your sodium limit — \(whole(mg)) of \(whole(sodiumLimitMg)) milligrams today."
                    : "You're at \(whole(mg)) of \(whole(sodiumLimitMg)) milligrams of sodium today."
            )
        }
    }

    /// Any tracked-or-askable nutrient ("How much protein have I had?").
    /// `target`/`mode` come from the Today slot config when the nutrient
    /// occupies a slot; nil target = plain total, no judgment.
    public static func nutrientStatus(
        nutrient: TrackedNutrient,
        value: Double,
        target: Double?,
        mode: TrackedMetricMode?
    ) -> Status {
        let name = nutrient.displayName.lowercased()
        let unit = spokenUnit(nutrient.unitSymbol, amount: value)
        guard let target, target > 0 else {
            return Status(
                headline: "\(whole(value)) \(nutrient.unitSymbol)",
                caption: name,
                spoken: "You've had \(whole(value)) \(unit) of \(name) today."
            )
        }
        let headline = "\(whole(value)) / \(whole(target)) \(nutrient.unitSymbol)"
        switch mode ?? nutrient.defaultMode {
        case .limit where value > target:
            return Status(
                headline: headline,
                caption: "\(name) — over limit",
                spoken: "You're over your \(name) limit — \(whole(value)) of \(whole(target)) \(unit) today."
            )
        case .goal where value >= target:
            return Status(
                headline: headline,
                caption: name,
                spoken: "\(name.capitalized) goal met — \(whole(value)) of \(whole(target)) \(unit) today."
            )
        default:
            return Status(
                headline: headline,
                caption: name,
                spoken: "You're at \(whole(value)) of \(whole(target)) \(unit) of \(name) today."
            )
        }
    }

    /// "grams", "milligrams", "ounces" — numbers are spoken, units
    /// should be too.
    private static func spokenUnit(_ symbol: String, amount: Double) -> String {
        let singular = amount == 1
        return switch symbol {
        case "g": singular ? "gram" : "grams"
        case "mg": singular ? "milligram" : "milligrams"
        case "oz": singular ? "ounce" : "ounces"
        case "µg", "mcg": singular ? "microgram" : "micrograms"
        default: symbol
        }
    }

    private static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}
