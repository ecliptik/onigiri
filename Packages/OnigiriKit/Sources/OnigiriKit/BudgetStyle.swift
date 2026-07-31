import Foundation

/// Whether being more active than planned earns more food.
///
/// Neither answer is more correct — it's how you want the app to behave,
/// so it's a setting rather than a decision baked into the math.
public enum ActivityCredit: String, CaseIterable, Sendable {
    /// Burn beyond the plan raises the day's budget; burn below it never
    /// lowers it. An active day earns a treat, and an unworn watch still
    /// costs nothing. The default.
    case earned
    /// The budget is the plan's number, full stop. Nothing measured moves
    /// it in either direction — the same figure all day, every day.
    case fixed

    public var label: String {
        switch self {
        case .earned: "Earn extra"
        case .fixed: "Fixed"
        }
    }

    public var explanation: String {
        switch self {
        case .earned: "Burning more than planned adds to the day's budget. Burning less never takes any away."
        case .fixed: "The day's budget is always your plan's number, whatever you burn."
        }
    }

    public static func resolve(_ raw: String?) -> ActivityCredit {
        raw.flatMap(ActivityCredit.init(rawValue:)) ?? .earned
    }
}

/// Where the plan's expected daily burn comes from.
public enum ExpectedBurnSource: String, CaseIterable, Sendable {
    /// Your own recent burn, recomputed as you go. The default.
    case automatic
    /// A number you set and the app leaves alone.
    case custom

    public var label: String {
        switch self {
        case .automatic: "Automatic"
        case .custom: "Custom"
        }
    }

    public static func resolve(_ raw: String?) -> ExpectedBurnSource {
        raw.flatMap(ExpectedBurnSource.init(rawValue:)) ?? .automatic
    }
}

public extension SharedStore {
    static let activityCreditKey = "activityCredit"
    static let expectedBurnSourceKey = "expectedBurnSource"
    static let customExpectedBurnKey = "customExpectedBurnKcal"

    static var activityCredit: ActivityCredit {
        ActivityCredit.resolve(defaults.string(forKey: activityCreditKey))
    }

    static var expectedBurnSource: ExpectedBurnSource {
        ExpectedBurnSource.resolve(defaults.string(forKey: expectedBurnSourceKey))
    }

    /// nil unless a custom burn is both selected AND set to something
    /// usable — a half-filled setting must never produce a 0 budget.
    static var customExpectedBurnKcal: Double? {
        guard expectedBurnSource == .custom else { return nil }
        let value = defaults.double(forKey: customExpectedBurnKey)
        return value > 0 ? value : nil
    }

    /// The average the plan should build on: the custom number when set,
    /// otherwise whatever the trailing Health read produced.
    static func planAverageBurn(measuredAverageKcal: Double?) -> Double? {
        customExpectedBurnKcal ?? measuredAverageKcal
    }
}
