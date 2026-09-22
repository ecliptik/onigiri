import Foundation
import Testing
@testable import OnigiriKit

struct GoalPrimeTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func prime(
        savedAt: Date, schema: Int = GoalPrime.currentSchema,
        weight: Double? = 200.2,
        history: [WeightTrend.Point]? = nil
    ) -> GoalPrime {
        GoalPrime(
            schema: schema, savedAt: savedAt, healthWeightLb: weight,
            averageBurnKcal: 2300, estimatedRestingKcal: 1743,
            weightHistory: history ?? [
                WeightTrend.Point(date: savedAt.addingTimeInterval(-86_400), weightLb: 200.9),
                WeightTrend.Point(date: savedAt, weightLb: 200.2),
            ],
            dailyTotals: [DayEnergyTotals(day: savedAt, intakeKcal: 1510, burnKcal: 2128)]
        )
    }

    @Test func roundTripsThroughJSON() throws {
        let original = prime(savedAt: noon)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GoalPrime.self, from: data)
        #expect(decoded == original)
        #expect(decoded.weightHistory.last?.weightLb == 200.2)
        #expect(decoded.dailyTotals.first?.burnKcal == 2128)
    }

    @Test func validForAWeekAndNeverFromTheFuture() {
        let p = prime(savedAt: noon)
        #expect(p.isValid(now: noon))
        #expect(p.isValid(now: noon.addingTimeInterval(2 * 86_400)),
                "a weight history does not belong to a calendar day")
        #expect(p.isValid(now: noon.addingTimeInterval(GoalPrime.maxAge)))
        #expect(!p.isValid(now: noon.addingTimeInterval(GoalPrime.maxAge + 1)))
        #expect(!p.isValid(now: noon.addingTimeInterval(-60)),
                "a prime stamped in the future has no knowable age")
        #expect(!prime(savedAt: noon, schema: GoalPrime.currentSchema + 1).isValid(now: noon))
    }

    @Test func sealedStoreIsNotTrustworthy() {
        #expect(!prime(savedAt: noon, weight: nil, history: []).isTrustworthy,
                "no weight and no history is a sealed store, not a fact about the scale")
        #expect(prime(savedAt: noon, weight: nil).isTrustworthy, "history alone says the store answered")
        #expect(prime(savedAt: noon, history: []).isTrustworthy, "one weigh-in alone does too")
    }
}
