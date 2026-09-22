import Foundation
import Testing
@testable import OnigiriKit

struct TodayPrimeTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func prime(
        day: Date, schema: Int = TodayPrime.currentSchema,
        summary: DailyEnergySummary = DailyEnergySummary(
            intakeKcal: 1510, activeBurnKcal: 385, restingBurnKcal: 1743, sodiumMg: 1550, waterOz: 24
        ),
        food: [FoodLogEntry] = [], water: [WaterLogEntry] = []
    ) -> TodayPrime {
        TodayPrime(
            schema: schema, day: Calendar.current.startOfDay(for: day), summary: summary,
            dayBurnKcal: 2128, estimatedRestingKcal: 1743, currentWeightLb: 190.4,
            averageBurnKcal: 2300, weeklyTrendLb: -0.2,
            weightHistory: [WeightTrend.Point(date: day, weightLb: 190.4)],
            trackedTotals: [1550, 24], foodLog: food, waterLog: water
        )
    }

    @Test func roundTripsThroughJSON() throws {
        let entry = FoodLogEntry(
            id: UUID(), name: "Chicken & rice", kcal: 600, sodiumMg: 550, date: noon,
            category: .lunch, nutrients: NutrientValues(proteinG: 42), editable: true,
            aiGenerated: false, quantity: 2,
            mealItems: [LoggedMealItem(name: "Chicken breast", kcal: 280)]
        )
        let water = WaterLogEntry(id: UUID(), oz: 12, date: noon)
        let original = prime(day: noon, food: [entry], water: [water])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TodayPrime.self, from: data)
        #expect(decoded == original)
        #expect(decoded.foodLog.first?.mealItems.first?.name == "Chicken breast")
        #expect(decoded.foodLog.first?.quantity == 2)
    }

    @Test func validOnlyForItsOwnDayAndSchema() {
        let p = prime(day: noon)
        #expect(p.isValid(now: noon))
        #expect(p.isValid(now: noon.addingTimeInterval(6 * 3600)))
        #expect(!p.isValid(now: noon.addingTimeInterval(86400)), "tomorrow primes nothing")
        #expect(!p.isValid(now: noon.addingTimeInterval(-86400)))
        #expect(!prime(day: noon, schema: TodayPrime.currentSchema + 1).isValid(now: noon))
    }

    @Test func sealedZeroDayIsNotTrustworthy() {
        let sealed = prime(day: noon, summary: .zero)
        #expect(!sealed.isTrustworthy)
        let emptyMorning = prime(day: noon, summary: DailyEnergySummary(
            intakeKcal: 0, activeBurnKcal: 0, restingBurnKcal: 3, sodiumMg: 0, waterOz: 0))
        #expect(emptyMorning.isTrustworthy, "resting burn alone says the store answered")
        let loggedOnly = prime(day: noon, summary: .zero,
                               water: [WaterLogEntry(id: UUID(), oz: 12, date: noon)])
        #expect(loggedOnly.isTrustworthy)
    }
}
