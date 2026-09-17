import Foundation
import Testing
@testable import OnigiriKit

struct CalendarPrimeTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func prime(
        savedAt: Date, schema: Int = CalendarPrime.currentSchema,
        totals: [DayEnergyTotals]? = nil
    ) -> CalendarPrime {
        CalendarPrime(
            schema: schema, savedAt: savedAt,
            totals: totals ?? [
                DayEnergyTotals(day: savedAt.addingTimeInterval(-86_400), intakeKcal: 1480, burnKcal: 2210),
                DayEnergyTotals(day: savedAt, intakeKcal: 1510, burnKcal: 2128),
            ],
            targetDeficitKcal: 300, isMaintenance: false,
            weightHistory: [WeightTrend.Point(date: savedAt, weightLb: 200.2)]
        )
    }

    @Test func roundTripsThroughJSON() throws {
        let original = prime(savedAt: noon)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CalendarPrime.self, from: data)
        #expect(decoded == original)
        #expect(decoded.totals.count == 2)
        #expect(decoded.targetDeficitKcal == 300)
    }

    @Test func validForAWeekAndNeverFromTheFuture() {
        let p = prime(savedAt: noon)
        #expect(p.isValid(now: noon))
        #expect(p.isValid(now: noon.addingTimeInterval(CalendarPrime.maxAge)))
        #expect(!p.isValid(now: noon.addingTimeInterval(CalendarPrime.maxAge + 1)))
        #expect(!p.isValid(now: noon.addingTimeInterval(-60)))
        #expect(!prime(savedAt: noon, schema: CalendarPrime.currentSchema + 1).isValid(now: noon))
    }

    @Test func aWindowWithNoEnergyIsASealedStore() {
        #expect(!prime(savedAt: noon, totals: []).isTrustworthy)
        #expect(!prime(savedAt: noon, totals: [
            DayEnergyTotals(day: noon, intakeKcal: 0, burnKcal: 0),
        ]).isTrustworthy)
        #expect(prime(savedAt: noon, totals: [
            DayEnergyTotals(day: noon, intakeKcal: 0, burnKcal: 3),
        ]).isTrustworthy, "resting burn alone says the store answered")
    }

    private func card(day: Date, summary: DailyEnergySummary? = nil) -> CalendarPrime.DayCard {
        CalendarPrime.DayCard(
            day: Calendar.current.startOfDay(for: day),
            summary: summary ?? DailyEnergySummary(
                intakeKcal: 1100, activeBurnKcal: 385, restingBurnKcal: 1743, sodiumMg: 1550, waterOz: 24),
            slotKeys: ["sodium", "protein"], slotTotals: [nil, 82]
        )
    }

    @Test func aV2281FileWithNoDayCardStillDecodes() throws {
        var json = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(prime(savedAt: noon))) as? [String: Any])
        json.removeValue(forKey: "dayCard")
        let decoded = try JSONDecoder().decode(
            CalendarPrime.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.dayCard == nil)
        #expect(decoded.totals.count == 2)
    }

    @Test func theDayCardRoundTripsWithItsNilSlot() throws {
        var original = prime(savedAt: noon)
        original.dayCard = card(day: noon)
        let decoded = try JSONDecoder().decode(
            CalendarPrime.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.dayCard?.slotTotals == [nil, 82])
    }

    @Test func theDayCardLastsUntilMidnightThoughTheMonthLastsAWeek() {
        let c = card(day: noon)
        #expect(c.isValid(now: noon))
        #expect(!c.isValid(now: noon.addingTimeInterval(86_400)),
                "yesterday's sodium under today's heading is a wrong number")
        var p = prime(savedAt: noon)
        p.dayCard = c
        #expect(p.isValid(now: noon.addingTimeInterval(86_400)), "the month is still good")
    }

    @Test func slotTotalsApplyOnlyUnderTheSettingsTheyWereReadAs() {
        let c = card(day: noon)
        #expect(c.slotTotals(ifReadAs: ["sodium", "protein"]) == [nil, 82])
        #expect(c.slotTotals(ifReadAs: ["sodium", "fiber"]) == nil,
                "82 g of protein is not 82 g of fiber")
    }

    @Test func aSealedDayCardIsNotTrustworthy() {
        #expect(!card(day: noon, summary: .zero).isTrustworthy)
        #expect(card(day: noon).isTrustworthy)
    }

    /// The contract in one test: the prime holds no verdicts, so a streak
    /// is whatever the raw days say on the day they are READ.
    @Test func carriesNoVerdicts() throws {
        let data = try JSONEncoder().encode(prime(savedAt: noon))
        let keys = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        ).keys
        #expect(!keys.contains { $0.lowercased().contains("streak") || $0.lowercased().contains("earned") })
    }
}
