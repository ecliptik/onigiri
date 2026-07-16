import Foundation
import Testing
@testable import OnigiriKit

/// The Goal chart's derivation rules — the WeightTrend primitives are
/// tested elsewhere; these pin their composition (windows, cutoffs,
/// domains) that lived untested in GoalView.
struct GoalTrendStatsTests {
    private static let cal = Calendar(identifier: .gregorian)
    private static let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12))!

    private static func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: now)!
    }

    /// A steady loss: one weigh-in per day dropping `slope` lb/day.
    private static func history(days: Int, startLb: Double, slope: Double) -> [WeightTrend.Point] {
        (0..<days).map { i in
            WeightTrend.Point(date: day(i - days + 1), weightLb: startLb + slope * Double(i))
        }
    }

    @Test func predictedComesFromWindowedDeficits() {
        // Ten 350-kcal days inside the window, one huge day outside it.
        let totals = (0..<10).map { DayEnergyTotals(day: Self.day(-$0), intakeKcal: 2000, burnKcal: 2350) }
            + [DayEnergyTotals(day: Self.day(-40), intakeKcal: 0, burnKcal: 99000)]
        let stats = GoalTrendStats.derive(
            weightHistory: [], smoothedHistory: [], dailyTotals: totals,
            targetWeightLb: nil, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        // 10 × 350 kcal = one pound of predicted LOSS (change is
        // signed, down = negative); the out-of-window day is ignored.
        #expect(stats.predicted30Lb == -1.0)
    }

    @Test func noLoggedDaysMeansNoPrediction() {
        let stats = GoalTrendStats.derive(
            weightHistory: [], smoothedHistory: [],
            dailyTotals: [DayEnergyTotals(day: Self.day(-45), intakeKcal: 2000, burnKcal: 2500)],
            targetWeightLb: nil, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.predicted30Lb == nil)
    }

    @Test func steadyLossProjectsATargetDate() throws {
        // 0.2 lb/day down from 200: 10 lb above the 190 target ≈ 50 days.
        let smoothed = Self.history(days: 30, startLb: 205.8, slope: -0.2)
        let stats = GoalTrendStats.derive(
            weightHistory: smoothed, smoothedHistory: smoothed, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        let projected = try #require(stats.projectedDate)
        let days = Self.cal.dateComponents([.day], from: Self.now, to: projected).day!
        #expect((45...55).contains(days))
    }

    @Test func flatTrendProjectsNothing() {
        let smoothed = Self.history(days: 30, startLb: 200, slope: 0)
        let stats = GoalTrendStats.derive(
            weightHistory: smoothed, smoothedHistory: smoothed, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.projectedDate == nil)
    }

    @Test func projectionsPastThreeYearsAreNoise() {
        // Barely-meaningful slope, 50 lb to go: thousands of days out.
        let smoothed = Self.history(days: 30, startLb: 240.6, slope: -0.02)
        let stats = GoalTrendStats.derive(
            weightHistory: smoothed, smoothedHistory: smoothed, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.projectedDate == nil)
    }

    @Test func domainPadsWeighInsAndTargetWhenLosing() {
        let history = [
            WeightTrend.Point(date: Self.day(-1), weightLb: 200),
            WeightTrend.Point(date: Self.day(0), weightLb: 198),
        ]
        let losing = GoalTrendStats.derive(
            weightHistory: history, smoothedHistory: history, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        #expect(losing.chartYDomain == 188...202)
        // Maintenance draws no target line — the stale target must not
        // stretch the domain.
        let maintaining = GoalTrendStats.derive(
            weightHistory: history, smoothedHistory: history, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: true,
            calendar: Self.cal, now: Self.now
        )
        #expect(maintaining.chartYDomain == 196...202)
    }

    @Test func emptyDataFallsBackToUnitDomain() {
        let stats = GoalTrendStats.derive(
            weightHistory: [], smoothedHistory: [], dailyTotals: [],
            targetWeightLb: nil, isMaintenance: true,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.chartYDomain == 0...1)
        #expect(stats == GoalTrendStats.empty)
    }
}
