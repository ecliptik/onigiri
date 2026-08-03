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
        sodiumLimitMg: Double,
        waterUnit: WaterUnit = .fluidOunces,
        sodiumUnit: SodiumUnit = .milligrams
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
            // Over/goal-met judged on the canonical values; only the
            // spoken/shown numbers convert.
            let met = plan.summary.waterOz >= waterGoalOz && waterGoalOz > 0
            let value = whole(waterUnit.fromOz(plan.summary.waterOz))
            let goal = whole(waterUnit.fromOz(waterGoalOz))
            let unit = waterUnit.spoken(waterUnit.fromOz(waterGoalOz))
            return Status(
                headline: "\(value) / \(goal) \(waterUnit.symbol)",
                caption: "water",
                spoken: met
                    ? "Water goal met — \(value) of \(goal) \(unit) today."
                    : "You're at \(value) of \(goal) \(unit) of water today."
            )
        case .sodium:
            let over = sodiumLimitMg > 0 && plan.summary.sodiumMg > sodiumLimitMg
            let digits = sodiumUnit.fractionDigits
            let value = amount(sodiumUnit.fromMg(plan.summary.sodiumMg), digits: digits)
            let limit = amount(sodiumUnit.fromMg(sodiumLimitMg), digits: digits)
            let name = sodiumUnit.nutrientName.lowercased()
            let unit = sodiumUnit.spoken(sodiumUnit.fromMg(sodiumLimitMg))
            return Status(
                headline: "\(value) / \(limit) \(sodiumUnit.symbol)",
                caption: over ? "\(name) — over limit" : name,
                spoken: over
                    ? "You're over your \(name) limit — \(value) of \(limit) \(unit) today."
                    : "You're at \(value) of \(limit) \(unit) of \(name) today."
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
        mode: TrackedMetricMode?,
        waterUnit: WaterUnit = .fluidOunces,
        sodiumUnit: SodiumUnit = .milligrams
    ) -> Status {
        // value/target arrive canonical (oz/mg); judgments stay on them.
        // Display/speech convert — and salt mode renames the nutrient.
        let name = nutrient.displayInlineName(sodium: sodiumUnit).lowercased()
        let symbol = nutrient.displayUnitSymbol(water: waterUnit, sodium: sodiumUnit)
        let digits = nutrient.displayFractionDigits(sodium: sodiumUnit)
        let displayValue = nutrient.displayValue(value, water: waterUnit, sodium: sodiumUnit)
        let shown = amount(displayValue, digits: digits)
        let unit = spokenUnit(symbol, amount: displayValue)
        guard let target, target > 0 else {
            return Status(
                headline: "\(shown) \(symbol)",
                caption: name,
                spoken: "You've had \(shown) \(unit) of \(name) today."
            )
        }
        let shownTarget = amount(nutrient.displayValue(target, water: waterUnit, sodium: sodiumUnit), digits: digits)
        let headline = "\(shown) / \(shownTarget) \(symbol)"
        switch mode ?? nutrient.defaultMode {
        case .limit where value > target:
            return Status(
                headline: headline,
                caption: "\(name) — over limit",
                spoken: "You're over your \(name) limit — \(shown) of \(shownTarget) \(unit) today."
            )
        case .goal where value >= target:
            return Status(
                headline: headline,
                caption: name,
                spoken: "\(name.capitalized) goal met — \(shown) of \(shownTarget) \(unit) today."
            )
        default:
            return Status(
                headline: headline,
                caption: name,
                spoken: "You're at \(shown) of \(shownTarget) \(unit) of \(name) today."
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
        case "mL": singular ? "milliliter" : "milliliters"
        default: symbol
        }
    }

    private static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// whole() with a decimal when the unit needs one (salt grams).
    private static func amount(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}
