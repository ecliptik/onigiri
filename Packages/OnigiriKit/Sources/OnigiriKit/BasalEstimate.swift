import Foundation

/// How much of the day is spent moving — the multiplier between resting
/// metabolism and total daily burn. Asked, not measured: it describes a
/// typical week, which is exactly what a steady budget wants and what a
/// rolling average of measured days can't give.
public enum ActivityLevel: String, CaseIterable, Sendable {
    case sedentary, light, moderate, active, veryActive

    public var label: String {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Lightly active"
        case .moderate: "Moderately active"
        case .active: "Active"
        case .veryActive: "Very active"
        }
    }

    public var detail: String {
        switch self {
        case .sedentary: "Desk work, little exercise"
        case .light: "Light exercise 1–3 days a week"
        case .moderate: "Moderate exercise 3–5 days a week"
        case .active: "Hard exercise 6–7 days a week"
        case .veryActive: "Physical job, or training twice a day"
        }
    }

    /// The standard multipliers applied to resting metabolism.
    public var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    public static func resolve(_ raw: String?) -> ActivityLevel {
        raw.flatMap(ActivityLevel.init(rawValue:)) ?? .light
    }
}

/// A daily burn estimated from the body rather than measured from it.
///
/// Measured burn is honest about yesterday and useless as a plan: it
/// drifts with the trailing average, and it silently under-reports the
/// hours a watch spent on a charger. An estimate is stable by
/// construction — it moves only when the body or the routine behind it
/// does, which is what a budget you can rely on needs.
///
/// Mifflin-St Jeor for the resting half (the best-validated of the common
/// predictive equations), times an activity factor for the rest.
public enum BasalEstimate {
    /// Only what the equation actually distinguishes. HealthKit's other
    /// values and "not set" all land on `unspecified`.
    public enum Sex: Sendable { case male, female, unspecified }

    /// Resting energy in kcal/day, or nil when the body isn't described
    /// well enough to be worth guessing from.
    public static func restingKcal(
        weightLb: Double, heightCm: Double, ageYears: Int, sex: Sex
    ) -> Double? {
        // Loose sanity bounds: nonsense in, nothing out. A silently wrong
        // budget is worse than a missing suggestion.
        guard weightLb > 40, weightLb < 1_000,
              heightCm > 90, heightCm < 260,
              ageYears > 12, ageYears < 120
        else { return nil }
        let kg = weightLb / 2.20462
        let constant: Double = switch sex {
        case .male: 5
        case .female: -161
        // The midpoint, so an unset or non-binary Health value still gets
        // a usable number instead of being forced into one of the two.
        case .unspecified: -78
        }
        return 10 * kg + 6.25 * heightCm - 5 * Double(ageYears) + constant
    }

    /// Total daily burn: resting × the activity factor, rounded to
    /// something a person would actually type.
    public static func dailyBurnKcal(
        weightLb: Double, heightCm: Double, ageYears: Int, sex: Sex,
        level: ActivityLevel
    ) -> Double? {
        guard let resting = restingKcal(
            weightLb: weightLb, heightCm: heightCm, ageYears: ageYears, sex: sex
        ) else { return nil }
        return (resting * level.factor / 10).rounded() * 10
    }
}

public extension SharedStore {
    static let activityLevelKey = "activityLevel"

    static var activityLevel: ActivityLevel {
        ActivityLevel.resolve(defaults.string(forKey: activityLevelKey))
    }
}
