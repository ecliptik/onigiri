import Testing
@testable import OnigiriKit

struct DailyEnergySummaryTests {
    @Test func balanceIsIntakeMinusTotalBurn() {
        let summary = DailyEnergySummary(
            intakeKcal: 1100, activeBurnKcal: 385, restingBurnKcal: 1120,
            sodiumMg: 1550, waterOz: 24
        )
        #expect(summary.totalBurnKcal == 1505)
        #expect(summary.balanceKcal == -405)
    }

    @Test func zeroStartsFlat() {
        #expect(DailyEnergySummary.zero.balanceKcal == 0)
        #expect(DailyEnergySummary.zero.totalBurnKcal == 0)
    }
}
