// Compiled into the app and watch targets directly — see
// LogWaterIntent.swift for why these must not live in the kit (linkd
// rejects SPM-delivered App Shortcuts metadata). The pure phrasing
// stays in the kit (StatusPhrasing) where its tests live.
import AppIntents
import OnigiriKit
import SwiftUI

/// The ask-back metrics Siri can answer about today (PLAN-siri 2.5):
/// "How many calories do I have left in Onigiri?" — spoken answer plus
/// a small snippet card, read LIVE from HealthKit through the same
/// DailyPlanLoader the app and widgets use.
enum StatusMetric: String, AppEnum {
    case caloriesLeft
    case water
    case sodium

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Today Metric"
    static let caseDisplayRepresentations: [StatusMetric: DisplayRepresentation] = [
        .caloriesLeft: "calories left",
        .water: "water",
        .sodium: "sodium",
    ]

    var phrasingMetric: StatusPhrasing.Metric {
        switch self {
        case .caloriesLeft: .caloriesLeft
        case .water: .water
        case .sodium: .sodium
        }
    }
}

/// One question, one metric parameter — Siri disambiguates naturally
/// and Shortcuts shows a single configurable tile.
struct CheckTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Today"
    static let description = IntentDescription(
        "Speaks today's calories left, water, or sodium from Apple Health.")

    @Parameter(title: "Metric", default: .caloriesLeft) var metric: StatusMetric

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$metric) today")
    }

    init() {}
    init(metric: StatusMetric) {
        self.metric = metric
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Live reads, not the widget mirror — a stale ask-back is worse
        // than a slow one (the reminder-staleness lesson, same day).
        let plan = await DailyPlanLoader.load(goal: WatchSync.loadGoal())
        let status = StatusPhrasing.phrase(
            metric: metric.phrasingMetric,
            plan: plan,
            waterGoalOz: SharedStore.waterGoalOz,
            sodiumLimitMg: SharedStore.sodiumLimitMg
        )
        return .result(dialog: IntentDialog(stringLiteral: status.spoken)) {
            TodayStatusSnippet(status: status)
        }
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
