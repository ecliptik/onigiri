import AppIntents
import OnigiriKit

/// "Describe a food in Onigiri" → "half a cup of rice and a fried egg"
/// → the describe-it model path, by voice. ALWAYS confirms the estimate
/// before anything is written to Health (the user's call, PLAN-siri):
/// an unreviewed estimate landing in the log is this flow's only real
/// risk. Lives in the app target — FoodIntelligence never enters the
/// kit — so only the phone's Siri offers it (no Foundation Models on
/// watchOS anyway).
struct DescribeFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Describe and Log Food"
    static let description = IntentDescription(
        "Estimates nutrition for a food you describe and logs it to Apple Health after you confirm.")

    @Parameter(title: "Food description", requestValueDialog: "What did you eat?")
    var foodDescription: String

    static var parameterSummary: some ParameterSummary {
        Summary("Estimate and log \(\.$foodDescription)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard FoodIntelligence.isAvailable else {
            throw DescribeLogError.unavailable
        }
        guard let food = await FoodIntelligence.describeFood(foodDescription) else {
            throw DescribeLogError.noEstimate
        }
        let kcal = food.kcal.formatted(.number.precision(.fractionLength(0)))
        let sodium = food.sodiumMg.formatted(.number.precision(.fractionLength(0)))
        // The confirmation IS the review step the in-app form provides
        // visually; declining throws and nothing is written.
        try await requestConfirmation(result: .result(dialog: IntentDialog(stringLiteral:
            "About \(kcal) calories and \(sodium) milligrams of sodium for \(food.name), \(food.serving). Log it?")))
        // nil category: the meal slot infers from time of day downstream,
        // same as any entry without explicit slot metadata.
        try await HealthKitService().logFood(
            name: food.name,
            kcal: food.kcal,
            sodiumMg: food.sodiumMg,
            // Estimated macros ride along now (PLAN-unified-search) —
            // same review contract: the spoken confirmation covers
            // kcal/sodium, the rest lands like any label's numbers.
            nutrients: food.nutrients,
            category: nil,
            aiGenerated: true
        )
        WidgetReloader.reloadNow(kinds: [
            WidgetKinds.gauge, WidgetKinds.streak, WidgetKinds.monthStats,
            WidgetKinds.todayCard,
        ])
        return .result(dialog: IntentDialog(stringLiteral:
            "Logged \(food.name) — \(kcal) calories."))
    }
}

private enum DescribeLogError: LocalizedError {
    case unavailable
    case noEstimate

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Describing food needs Apple Intelligence, which isn't available on this device."
        case .noEstimate:
            "Couldn't estimate that — try describing the food and portion differently."
        }
    }
}
