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

    /// A weigh-in at a wall-clock hour on an offset day (`now` is 12:00).
    private static func at(_ dayOffset: Int, hour: Int) -> Date {
        cal.date(byAdding: DateComponents(day: dayOffset, hour: hour - 12), to: now)!
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
            weightHistory: [], dailyTotals: totals,
            targetWeightLb: nil, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        // 10 × 350 kcal = one pound of predicted LOSS (change is
        // signed, down = negative); the out-of-window day is ignored.
        #expect(stats.predicted30Lb == -1.0)
    }

    @Test func noLoggedDaysMeansNoPrediction() {
        let stats = GoalTrendStats.derive(
            weightHistory: [],
            dailyTotals: [DayEnergyTotals(day: Self.day(-45), intakeKcal: 2000, burnKcal: 2500)],
            targetWeightLb: nil, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.predicted30Lb == nil)
    }

    @Test func steadyLossProjectsATargetDate() throws {
        // 0.2 lb/day down from 200: 10 lb above the 190 target ≈ 50 days.
        let history = Self.history(days: 30, startLb: 205.8, slope: -0.2)
        let stats = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        let projected = try #require(stats.projectedDate)
        let days = Self.cal.dateComponents([.day], from: Self.now, to: projected).day!
        #expect((45...55).contains(days))
    }

    @Test func flatTrendProjectsNothing() {
        let history = Self.history(days: 30, startLb: 200, slope: 0)
        let stats = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.projectedDate == nil)
    }

    @Test func projectionsPastThreeYearsAreNoise() {
        // Barely-meaningful slope, 50 lb to go: thousands of days out.
        let history = Self.history(days: 30, startLb: 240.6, slope: -0.02)
        let stats = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.projectedDate == nil)
    }

    @Test func freshDietOutweighsAFlatPriorWeek() throws {
        // Six flat days around 219 (two weigh-ins a day), then a week
        // losing 2 lb/week down to 217, target 210 — the shape that
        // motivated the recency-weighted fit. An unweighted fit over
        // the same window reads ~1 lb/week and quotes ~50 days; the
        // old fit-the-moving-average read even less. Weighted: ~40.
        var history: [WeightTrend.Point] = []
        for i in 0..<6 {
            let d = i - 13
            history.append(.init(date: Self.at(d, hour: 7), weightLb: 218.25))
            history.append(.init(date: Self.at(d, hour: 20), weightLb: 219.75))
        }
        for i in 0...7 {
            let d = i - 7
            let trend = 219.0 - 2.0 * Double(i) / 7.0
            history.append(.init(date: Self.at(d, hour: 7), weightLb: trend - 0.75))
            if i < 7 {
                history.append(.init(date: Self.at(d, hour: 20), weightLb: trend + 0.75))
            }
        }
        let stats = GoalTrendStats.derive(
            weightHistory: history,
            dailyTotals: [],
            targetWeightLb: 210, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        let projected = try #require(stats.projectedDate)
        let days = Self.cal.dateComponents([.day], from: Self.now, to: projected).day!
        #expect((37...44).contains(days))
    }

    @Test func sparseWeeklyWeighInsStillProject() throws {
        // One weigh-in a week, 1 lb/week down, 8 lb to go ≈ 56 days.
        let history = (0...3).map {
            WeightTrend.Point(date: Self.day(-7 * (3 - $0)), weightLb: 221 - Double($0))
        }
        let stats = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: 210, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        let projected = try #require(stats.projectedDate)
        let days = Self.cal.dateComponents([.day], from: Self.now, to: projected).day!
        #expect((54...58).contains(days))
    }

    @Test func aWeekendOfWeighInsProjectsNothing() {
        // Two days of plunging readings — no projection until weigh-ins
        // cover three distinct days across a full week.
        let history = [
            WeightTrend.Point(date: Self.at(-1, hour: 7), weightLb: 221),
            WeightTrend.Point(date: Self.at(-1, hour: 20), weightLb: 220),
            WeightTrend.Point(date: Self.at(0, hour: 7), weightLb: 219),
        ]
        let stats = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: 210, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.projectedDate == nil)
    }

    @Test func sixDailyWeighInsAreTooYoungToProject() {
        // A clear loss, but the history is only six days deep — the
        // span gate holds until a full week exists.
        let history = (0..<6).map {
            WeightTrend.Point(date: Self.day($0 - 5), weightLb: 220 - 0.3 * Double($0))
        }
        let stats = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: 210, isMaintenance: false,
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
            weightHistory: history, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        #expect(losing.chartYDomain == 188...202)
        // Maintenance draws the hold-near anchor line, so a set anchor
        // stretches the domain exactly like a lose target…
        let anchored = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: true,
            calendar: Self.cal, now: Self.now
        )
        #expect(anchored.chartYDomain == 188...202)
        // …while the 0 "no anchor parked" placeholder must not drag the
        // domain to zero.
        let anchorless = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: 0, isMaintenance: true,
            calendar: Self.cal, now: Self.now
        )
        #expect(anchorless.chartYDomain == 196...202)
    }

    @Test func maintenanceReadsDriftInsteadOfProjecting() throws {
        // The same steady loss that projects a date in lose mode reads
        // as drift in maintenance — and never a projection, even with
        // the parked target still on the record.
        let history = Self.history(days: 30, startLb: 205.8, slope: -0.2)
        let stats = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: true,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.projectedDate == nil)
        let drift = try #require(stats.driftLbPerWeek)
        #expect(abs(drift - (-1.4)) < 0.05)
    }

    @Test func loseModeReadsNoDrift() {
        let history = Self.history(days: 30, startLb: 205.8, slope: -0.2)
        let stats = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: 190, isMaintenance: false,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.driftLbPerWeek == nil)
    }

    @Test func flatMaintenanceReadsSteady() throws {
        let history = Self.history(days: 30, startLb: 200, slope: 0)
        let stats = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: nil, isMaintenance: true,
            calendar: Self.cal, now: Self.now
        )
        let drift = try #require(stats.driftLbPerWeek)
        #expect(abs(drift) < GoalTrendStats.steadyDriftThresholdLbPerWeek)
    }

    @Test func driftGatesOnYoungDataLikeTheProjection() {
        // Six days of clear movement — same span gate as lose mode.
        let history = (0..<6).map {
            WeightTrend.Point(date: Self.day($0 - 5), weightLb: 200 + 0.3 * Double($0))
        }
        let stats = GoalTrendStats.derive(
            weightHistory: history, dailyTotals: [],
            targetWeightLb: nil, isMaintenance: true,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.driftLbPerWeek == nil)
    }

    @Test func emptyDataFallsBackToUnitDomain() {
        let stats = GoalTrendStats.derive(
            weightHistory: [], dailyTotals: [],
            targetWeightLb: nil, isMaintenance: true,
            calendar: Self.cal, now: Self.now
        )
        #expect(stats.chartYDomain == 0...1)
        #expect(stats == GoalTrendStats.empty)
    }
}
