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
    // Every macro is askable regardless of which two the Today screen
    // tracks — slots change, Siri shouldn't forget how to answer. When
    // the nutrient DOES occupy a slot, the answer speaks its target.
    case protein
    case carbs
    case fat
    case saturatedFat
    case fiber
    case sugar
    case cholesterol
    case caffeine

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Today Metric"
    static let caseDisplayRepresentations: [StatusMetric: DisplayRepresentation] = [
        .caloriesLeft: "calories left",
        .water: "water",
        .sodium: "sodium",
        .protein: "protein",
        .carbs: "carbs",
        .fat: "fat",
        .saturatedFat: "saturated fat",
        .fiber: "fiber",
        .sugar: "sugar",
        .cholesterol: "cholesterol",
        .caffeine: "caffeine",
    ]

    /// The three originals route through the plan summary; nil means
    /// "read this nutrient's day total live from HealthKit".
    var phrasingMetric: StatusPhrasing.Metric? {
        switch self {
        case .caloriesLeft: .caloriesLeft
        case .water: .water
        case .sodium: .sodium
        default: nil
        }
    }

    var nutrient: TrackedNutrient? {
        switch self {
        case .caloriesLeft, .water, .sodium: nil
        case .protein: .protein
        case .carbs: .carbs
        case .fat: .fat
        case .saturatedFat: .saturatedFat
        case .fiber: .fiber
        case .sugar: .sugar
        case .cholesterol: .cholesterol
        case .caffeine: .caffeine
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
        let status: StatusPhrasing.Status
        if let phrasingMetric = metric.phrasingMetric {
            let plan = await DailyPlanLoader.load(goal: WatchSync.loadGoal())
            status = StatusPhrasing.phrase(
                metric: phrasingMetric,
                plan: plan,
                waterGoalOz: SharedStore.waterGoalOz,
                sodiumLimitMg: SharedStore.sodiumLimitMg,
                waterUnit: SharedStore.waterUnit,
                sodiumUnit: SharedStore.sodiumUnit
            )
        } else if let nutrient = metric.nutrient {
            let value = (try? await HealthKitService().dayTotal(of: nutrient, for: .now)) ?? 0
            // Target and goal/limit judgment come from the Today slot
            // config when this nutrient occupies a slot; otherwise the
            // answer is a plain total.
            let slot = [1, 2].first { SharedStore.trackedNutrient(slot: $0) == nutrient }
            status = StatusPhrasing.nutrientStatus(
                nutrient: nutrient,
                value: value,
                target: slot.map { SharedStore.trackedTarget(slot: $0, nutrient: nutrient) },
                mode: slot.map { SharedStore.trackedMode(slot: $0, nutrient: nutrient) },
                waterUnit: SharedStore.waterUnit,
                sodiumUnit: SharedStore.sodiumUnit
            )
        } else {
            // Unreachable by construction — every case maps to one arm.
            throw CheckTodayError.unavailable
        }
        return .result(dialog: IntentDialog(stringLiteral: status.spoken)) {
            TodayStatusSnippet(status: status)
        }
    }
}

private enum CheckTodayError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Couldn't read today's data from Apple Health."
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
