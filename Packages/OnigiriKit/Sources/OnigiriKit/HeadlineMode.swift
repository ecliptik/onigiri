import SwiftUI

/// What the big Today/watch/widget calorie number shows. Tapping the phone
/// headline cycles it; the choice persists on `balanceStyle` (the raw key
/// kept its name for back-compat and watch-sync) and every surface renders
/// the same mode through `headlineReadout`, so they can't drift.
public enum HeadlineMode: String, CaseIterable, Sendable {
    /// Budget minus intake — "kcal left" to eat toward the goal. The
    /// historical default, so an unset/unknown value reads as this.
    case remaining
    /// ± intake − burn. Negative is a deficit (good).
    case balance
    /// Straight intake so far today.
    case eaten
    /// The day's calorie budget itself.
    case budget

    /// The modes the tap cycles through. Without a budget (no goal, or a
    /// goal missing its weight/date) "left" and "budget" have no value, so
    /// the cycle collapses to balance ↔ eaten.
    public static func available(hasBudget: Bool) -> [HeadlineMode] {
        hasBudget ? [.remaining, .balance, .eaten, .budget] : [.balance, .eaten]
    }

    /// The next mode when the number is tapped, skipping any that the
    /// current budget can't fill.
    public func next(hasBudget: Bool) -> HeadlineMode {
        let modes = Self.available(hasBudget: hasBudget)
        let index = modes.firstIndex(of: self) ?? -1
        return modes[(index + 1) % modes.count]
    }

    /// The mode actually shown: a stored-but-unavailable mode (e.g.
    /// "budget" after the goal was cleared) falls back to balance.
    public func resolved(hasBudget: Bool) -> HeadlineMode {
        Self.available(hasBudget: hasBudget).contains(self) ? self : .balance
    }
}

public extension CalorieBudget {
    /// Everything a surface needs to render the headline for one mode:
    /// the number, its caption, whether it carries an explicit ± sign
    /// (balance only), its tint, and the VoiceOver twin of that tint.
    struct HeadlineReadout: Equatable, Sendable {
        public let value: Double
        public let caption: String
        public let signed: Bool
        public let tint: Color
        public let statusLabel: String?
    }

    /// The one shared answer to "show this mode as what?", so Today, the
    /// watch, the widgets, and the complications stay identical.
    static func headlineReadout(
        mode: HeadlineMode,
        summary: DailyEnergySummary,
        dailyBudgetKcal: Double?
    ) -> HeadlineReadout {
        switch mode.resolved(hasBudget: dailyBudgetKcal != nil) {
        case .remaining:
            let remaining = (dailyBudgetKcal ?? 0) - summary.intakeKcal
            let headline = remainingHeadline(remaining)
            return HeadlineReadout(
                value: headline.value, caption: headline.caption, signed: false,
                tint: .remainingStatus(kcal: remaining),
                statusLabel: Color.remainingStatusLabel(kcal: remaining)
            )
        case .balance:
            let balance = summary.balanceKcal
            return HeadlineReadout(
                value: balance, caption: "kcal balance", signed: true,
                tint: balance <= 0 ? .green : .orange,
                statusLabel: balance <= 0 ? "deficit" : "surplus"
            )
        case .eaten:
            return HeadlineReadout(
                value: summary.intakeKcal, caption: "kcal eaten", signed: false,
                tint: .primary, statusLabel: nil
            )
        case .budget:
            return HeadlineReadout(
                value: dailyBudgetKcal ?? 0, caption: "kcal budget", signed: false,
                tint: .riceToast, statusLabel: nil
            )
        }
    }
}
