#if canImport(WidgetKit) && canImport(HealthKit)
import SwiftUI
import WidgetKit

/// The accessory-family renderings (watch complications and iPhone
/// lock-screen widgets) live in the kit so the two surfaces are one
/// definition and can't drift.

public struct BalanceAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let state: DailyPlanLoader.State
    let showsRemaining: Bool
    let needsSetup: Bool

    public init(state: DailyPlanLoader.State, showsRemaining: Bool, needsSetup: Bool) {
        self.state = state
        self.showsRemaining = showsRemaining
        self.needsSetup = needsSetup
    }

    /// The headline number in the user's chosen style: (value, positive-is-good).
    private var headline: (kcal: Double, goodAboveZero: Bool) {
        if showsRemaining, let remaining = state.remainingKcal {
            return (remaining, true)
        }
        return (state.summary.balanceKcal, false)
    }

    private var headlineText: Text {
        let (kcal, goodAboveZero) = headline
        return goodAboveZero
            ? Text("\(kcal, format: .number.precision(.fractionLength(0))) kcal left")
            : Text("\(kcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))) kcal")
    }

    private var headlineColor: Color {
        let (kcal, goodAboveZero) = headline
        return (goodAboveZero ? kcal >= 0 : kcal <= 0) ? .green : .orange
    }

    public var body: some View {
        if needsSetup {
            setupHint
        } else {
            complication
        }
    }

    /// Pre-authorization: say what to do instead of a confident zero.
    @ViewBuilder
    private var setupHint: some View {
        switch family {
        case .accessoryInline:
            Text("\(SharedStore.rewardEmoji) Open Onigiri to set up")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Text(SharedStore.rewardEmoji)
                Text("Open Onigiri\nto set up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        #if os(watchOS)
        case .accessoryCorner:
            Text(SharedStore.rewardEmoji)
                .font(.system(size: 20))
                .widgetLabel { Text("Set up Onigiri") }
        #endif
        default:
            Gauge(value: 0) {
                Text(SharedStore.rewardEmoji).font(.system(size: 12))
            } currentValueLabel: {
                Text("—")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }

    @ViewBuilder
    private var complication: some View {
        switch family {
        case .accessoryInline:
            Text("\(SharedStore.rewardEmoji) ").font(.body) + headlineText
        #if os(watchOS)
        case .accessoryCorner:
            // The badge in the corner, the headline on the curve.
            Text(SharedStore.rewardEmoji)
                .font(.system(size: 20))
                .widgetLabel {
                    headlineText
                        .foregroundStyle(headlineColor)
                }
        #endif
        case .accessoryRectangular:
            HStack(spacing: 8) {
                OnigiriGauge(progress: state.gaugeProgress)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    headlineText
                        .font(.headline.weight(.bold))
                        .foregroundStyle(headlineColor)
                    if let target = state.deficitTargetKcal, target > 0 {
                        Text("\(Int(state.gaugeProgress * 100))% of daily goal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(state.summary.waterOz, format: .number.precision(.fractionLength(0))) oz water")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            // The ring mimics Today's headline ring: how much of the
            // day's calorie budget is eaten, orange when over. Without
            // a plan it falls back to goal progress.
            let eaten = state.dailyBudgetKcal.map { budget in
                budget > 0 ? min(1, state.summary.intakeKcal / budget) : 0
            }
            let over = state.dailyBudgetKcal.map { state.summary.intakeKcal > $0 } ?? false
            Gauge(value: eaten ?? state.gaugeProgress) {
                Text(SharedStore.rewardEmoji)
                    .font(.system(size: 12))
            } currentValueLabel: {
                Text(headline.kcal, format: headline.goodAboveZero
                    ? .number.precision(.fractionLength(0))
                    : .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(headlineColor)
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(over ? .orange : .green)
        }
    }
}

public struct WaterAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let waterOz: Double
    let goalOz: Double
    let needsSetup: Bool

    public init(waterOz: Double, goalOz: Double, needsSetup: Bool) {
        self.waterOz = waterOz
        self.goalOz = goalOz
        self.needsSetup = needsSetup
    }

    public var body: some View {
        switch family {
        case .accessoryInline:
            if needsSetup {
                Text("💧 Open Onigiri to set up")
            } else {
                Text("💧 \(waterOz, format: .number.precision(.fractionLength(0))) of \(goalOz, format: .number.precision(.fractionLength(0))) oz")
            }
        #if os(watchOS)
        case .accessoryCorner:
            Image(systemName: "drop.fill")
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .widgetLabel {
                    needsSetup
                        ? Text("Set up Onigiri")
                        : Text("\(waterOz, format: .number.precision(.fractionLength(0)))/\(goalOz, format: .number.precision(.fractionLength(0))) oz")
                }
        #endif
        default:
            Gauge(value: needsSetup ? 0 : min(waterOz, goalOz), in: 0...max(1, goalOz)) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                needsSetup
                    ? Text("—")
                    : Text(waterOz, format: .number.precision(.fractionLength(0)))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.blue)
        }
    }
}

/// The streak, judged exactly like the Calendar tab (per-day snapshot
/// targets, untracked threshold, completed days only) — shared by the
/// iPhone streak widget and the watch streak complication.
@MainActor
public enum StreakLoader {
    public static func load() async -> (streak: Int, needsSetup: Bool) {
        let needsSetup = await PlanCache.needsSetup()
        let state = await PlanCache.state(goal: WatchSync.loadGoal())
        let totals = await PlanCache.energyTotals()
        let earned = StreakCalendar.earnedDays(
            totals: totals,
            targetDeficitKcal: state.deficitTargetKcal,
            targetsByDay: DeficitTargetHistory.targetsByDay(),
            untrackedBelowKcal: SharedStore.untrackedBelowKcal
        )
        return (StreakCalendar.currentStreak(earned: earned), needsSetup)
    }
}

/// The streak's accessory-family rendering, shared across surfaces.
public struct StreakAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let streak: Int
    let needsSetup: Bool

    public init(streak: Int, needsSetup: Bool) {
        self.streak = streak
        self.needsSetup = needsSetup
    }

    public var body: some View {
        switch family {
        case .accessoryInline:
            if needsSetup {
                Text("\(SharedStore.rewardEmoji) Open Onigiri to set up")
            } else {
                Text("\(SharedStore.rewardEmoji) \(streak)-day streak")
            }
        #if os(watchOS)
        case .accessoryCorner:
            Text(SharedStore.rewardEmoji)
                .font(.system(size: 20))
                .widgetLabel {
                    Text(needsSetup ? "Set up Onigiri" : "\(streak)-day streak")
                }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Text(SharedStore.rewardEmoji)
                    .font(.system(size: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text(needsSetup ? "—" : "\(streak) \(streak == 1 ? "day" : "days")")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(streak > 0 && !needsSetup ? Color.green : Color.secondary)
                    Text(needsSetup ? "Open Onigiri to set up" : "current streak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        #endif
        default:
            VStack(spacing: 0) {
                Text(SharedStore.rewardEmoji)
                    .font(.system(size: 16))
                Text(needsSetup ? "—" : "\(streak)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
    }
}
#endif
