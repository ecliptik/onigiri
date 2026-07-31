import Foundation

/// How the day's calorie budget behaves. ONE choice, because the two it
/// replaced ("expected burn" and "active days") were never independent in
/// practice — you either want the app to follow your body, or you want a
/// number that sits still (the user, 2026-07-30).
public enum BudgetStyle: String, CaseIterable, Sendable {
    /// Follows your recent burn, and burning more than planned adds to
    /// the day's budget. The historical behavior, and the default.
    case automatic
    /// The same budget every day. Nothing measured moves it in either
    /// direction — which is what makes taking the watch off free.
    case fixed

    public var label: String {
        switch self {
        case .automatic: "Automatic"
        case .fixed: "Fixed"
        }
    }

    /// Shown under the picker for whichever one is selected, so the
    /// choice explains itself instead of needing the wiki.
    ///
    /// Both open with the same four words on purpose. The question being
    /// asked is only ever "does what I can eat move?", and the first
    /// wording answered it in the app's vocabulary — budget, burn,
    /// planned — which is exactly the vocabulary someone reading a
    /// settings screen hasn't learned yet (the user, 2026-07-30).
    public var explanation: String {
        switch self {
        case .automatic: "Your daily calorie budget goes up when you're active."
        case .fixed: "Your daily calorie budget stays the same."
        }
    }

    /// Whether measured burn is allowed to raise the day's budget.
    public var creditsActivity: Bool { self == .automatic }

    public static func resolve(_ raw: String?) -> BudgetStyle {
        if let style = raw.flatMap(BudgetStyle.init(rawValue:)) { return style }
        // Continuity for the short-lived two-picker version: its
        // "activityCredit" key carried the same distinction under other
        // names, and silently reverting someone's Fixed to Automatic
        // would look like the setting didn't stick.
        return SharedStore.defaults.string(forKey: SharedStore.legacyActivityCreditKey) == "fixed"
            ? .fixed : .automatic
    }
}

public extension SharedStore {
    static let budgetStyleKey = "budgetStyle"
    /// Retired 2026-07-30; still read once, by BudgetStyle.resolve.
    static let legacyActivityCreditKey = "activityCredit"
    /// Only meaningful under `.fixed`, and only when set.
    static let customExpectedBurnKey = "customExpectedBurnKcal"

    static var budgetStyle: BudgetStyle {
        BudgetStyle.resolve(defaults.string(forKey: budgetStyleKey))
    }

    /// The pinned burn, when there is one. A blank field under Fixed is
    /// not an error — the plan just keeps using your recent average, so a
    /// half-finished setting can never produce a zero budget.
    static var customExpectedBurnKcal: Double? {
        guard budgetStyle == .fixed else { return nil }
        let value = defaults.double(forKey: customExpectedBurnKey)
        return value > 0 ? value : nil
    }

    /// The average the plan should build on: the pinned number when set,
    /// otherwise whatever the trailing Health read produced.
    static func planAverageBurn(measuredAverageKcal: Double?) -> Double? {
        customExpectedBurnKcal ?? measuredAverageKcal
    }
}
