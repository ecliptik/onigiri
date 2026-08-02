import Foundation

/// Resting energy estimated from the body rather than measured from it.
///
/// This is the FLOOR under the day's resting credit, and the reason
/// resting can be credited up front at midnight instead of dripping in
/// hourly: it's the predictable part of the day, it happens whether or
/// not you move, and Health hasn't recorded it yet at breakfast.
///
/// Mifflin-St Jeor — the best-validated of the common predictive
/// equations. There is no activity multiplier on top: active energy is
/// EARNED from what the watch actually recorded, never estimated, which
/// is what makes wearing it worth something (2026-08-02).
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
}
