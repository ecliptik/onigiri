#if canImport(HealthKit) && canImport(WidgetKit)
import AppIntents
import SwiftUI

/// The ask-back metrics Siri can answer about today (PLAN-siri 2.5):
/// "How many calories do I have left in Onigiri?" — spoken answer plus
/// a small snippet card, read LIVE from HealthKit through the same
/// DailyPlanLoader the app and widgets use.
public enum StatusMetric: String, AppEnum {
    case caloriesLeft
    case water
    case sodium

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Today Metric"
    public static let caseDisplayRepresentations: [StatusMetric: DisplayRepresentation] = [
        .caloriesLeft: "calories left",
        .water: "water",
        .sodium: "sodium",
    ]
}

/// One question, one metric parameter — Siri disambiguates naturally
/// and Shortcuts shows a single configurable tile.
public struct CheckTodayIntent: AppIntent {
    public static let title: LocalizedStringResource = "Check Today"
    public static let description = IntentDescription(
        "Speaks today's calories left, water, or sodium from Apple Health.")

    @Parameter(title: "Metric", default: .caloriesLeft) public var metric: StatusMetric

    public static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$metric) today")
    }

    public init() {}
    public init(metric: StatusMetric) {
        self.metric = metric
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Live reads, not the widget mirror — a stale ask-back is worse
        // than a slow one (the reminder-staleness lesson, same day).
        let plan = await DailyPlanLoader.load(goal: WatchSync.loadGoal())
        let status = StatusPhrasing.phrase(
            metric: metric,
            plan: plan,
            waterGoalOz: SharedStore.waterGoalOz,
            sodiumLimitMg: SharedStore.sodiumLimitMg
        )
        return .result(dialog: IntentDialog(stringLiteral: status.spoken)) {
            TodayStatusSnippet(status: status)
        }
    }
}

/// The pure half, unit-tested: numbers in, headline + caption + spoken
/// sentence out. Mirrors the app's own grammar (remainingHeadline's
/// "kcal left"/"kcal over", the hydration row's "X / Y oz").
public enum StatusPhrasing {
    public struct Status: Sendable, Equatable {
        public let headline: String
        public let caption: String
        public let spoken: String
    }

    public static func phrase(
        metric: StatusMetric,
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

    private static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

/// The snippet card under Siri's spoken answer: headline number,
/// caption, on the brand's warm canvas.
struct TodayStatusSnippet: View {
    let status: StatusPhrasing.Status

    var body: some View {
        HStack(spacing: 12) {
            Text("🍙")
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.headline)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.riceToast)
                Text(status.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }
}
#endif
