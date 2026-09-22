import Foundation
import Testing
@testable import OnigiriKit

struct StreakCalendarTests {
    private let calendar = Calendar.current

    private func day(_ offset: Int) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: .now)!)
    }

    private func totals(_ offset: Int, intake: Double, burn: Double) -> DayEnergyTotals {
        DayEnergyTotals(day: day(offset), intakeKcal: intake, burnKcal: burn)
    }

    @Test func earnsOnlyWhenTargetMetAndFoodLogged() {
        let history = [
            totals(-3, intake: 1500, burn: 2300),  // deficit 800 ≥ 600 → earned
            totals(-2, intake: 2000, burn: 2300),  // deficit 300 < 600 → no
            totals(-1, intake: 0, burn: 2300),     // nothing logged → no credit
        ]
        let earned = StreakCalendar.earnedDays(totals: history, fallbackRule: .deficitTarget(600))
        #expect(earned == [day(-3)])
    }

    @Test func anyDeficitEarnsWithoutGoal() {
        let history = [
            totals(-2, intake: 1500, burn: 1600),  // deficit 100 → earned
            totals(-1, intake: 1700, burn: 1600),  // surplus → no
        ]
        let earned = StreakCalendar.earnedDays(totals: history, fallbackRule: .anyDeficit)
        #expect(earned == [day(-2)])
    }

    @Test func maintenanceBandScoresAdherenceNotRestriction() {
        let history = [
            totals(-5, intake: 2250, burn: 2300),  // 50 under → earned
            totals(-4, intake: 2380, burn: 2300),  // 80 over → earned
            totals(-3, intake: 2150, burn: 2300),  // 150 under → NOT earned
            totals(-2, intake: 2450, burn: 2300),  // 150 over → no
            totals(-1, intake: 2200, burn: 2300),  // exactly at the band edge → earned
        ]
        let earned = StreakCalendar.earnedDays(totals: history, fallbackRule: .maintenanceBand)
        #expect(earned == [day(-5), day(-4), day(-1)])
    }

    @Test func todayNeverEarnsMidDay() {
        // A comfortable deficit right now still isn't a badge — the day
        // has to COMPLETE (a live "earned" at breakfast read as broken).
        let history = [
            totals(0, intake: 1500, burn: 2400),
            totals(-1, intake: 1500, burn: 2400),
        ]
        let earned = StreakCalendar.earnedDays(totals: history, fallbackRule: .deficitTarget(600))
        #expect(earned == [day(-1)])
    }

    @Test func perDaySnapshotRulesBeatTheCurrentRule() {
        let history = [
            totals(-4, intake: 1500, burn: 2300),  // deficit 800
            totals(-3, intake: 1500, burn: 2300),  // deficit 800
            totals(-2, intake: 1900, burn: 2300),  // deficit 400
            totals(-1, intake: 2250, burn: 2300),  // deficit 50
        ]
        // Today's rule is a demanding 900 — but the days were lived
        // under snapshots: 600 (met), none (falls back to 900: missed),
        // the no-goal any-deficit rule (met), and a maintenance day
        // whose near-even 50 earns under the band.
        let earned = StreakCalendar.earnedDays(
            totals: history,
            fallbackRule: .deficitTarget(900),
            rulesByDay: [
                day(-4): .deficitTarget(600),
                day(-2): .anyDeficit,
                day(-1): .maintenanceBand,
            ]
        )
        #expect(earned == [day(-4), day(-2), day(-1)])
    }

    @Test func untrackedThresholdExcludesSparseDays() {
        let history = [
            totals(-2, intake: 400, burn: 2300),   // sparse: huge "deficit" but untracked
            totals(-1, intake: 1500, burn: 2300),  // tracked, deficit 800 → earned
        ]
        let earned = StreakCalendar.earnedDays(
            totals: history, fallbackRule: .deficitTarget(600), untrackedBelowKcal: 1000
        )
        #expect(earned == [day(-1)])
        #expect(!StreakCalendar.isTracked(history[0], untrackedBelowKcal: 1000))
        #expect(StreakCalendar.isTracked(history[1], untrackedBelowKcal: 1000))
        // Threshold 0 keeps the old any-logging rule.
        #expect(StreakCalendar.isTracked(history[0], untrackedBelowKcal: 0))
    }

    @Test func streakCountsBackFromToday() {
        let earned: Set<Date> = [day(0), day(-1), day(-2)]
        #expect(StreakCalendar.currentStreak(earned: earned) == 3)
    }

    @Test func inProgressTodayDoesNotBreakStreak() {
        let earned: Set<Date> = [day(-1), day(-2), day(-3)]
        #expect(StreakCalendar.currentStreak(earned: earned) == 3)
    }

    @Test func gapBreaksStreak() {
        let earned: Set<Date> = [day(-1), day(-3), day(-4)]
        #expect(StreakCalendar.currentStreak(earned: earned) == 1)
    }

    @Test func noEarnedDaysMeansZeroStreak() {
        #expect(StreakCalendar.currentStreak(earned: []) == 0)
    }

    @Test func bestStreakFindsTheLongestRunAnywhere() {
        // A 2-run ending today and an older 4-run: best is 4.
        let earned: Set<Date> = [day(0), day(-1), day(-10), day(-11), day(-12), day(-13)]
        #expect(StreakCalendar.bestStreak(earned: earned) == 4)
        #expect(StreakCalendar.bestStreak(earned: []) == 0)
        #expect(StreakCalendar.bestStreak(earned: [day(-3)]) == 1)
    }

    @Test func monthCountOnlyCountsThatMonth() {
        // Pick a stable reference: the 15th of this month, with earned days
        // this month and one ~40 days earlier (previous month).
        let midMonth = calendar.date(bySetting: .day, value: 15, of: .now)!
        let inMonth = calendar.startOfDay(for: midMonth)
        let earlier = calendar.date(byAdding: .day, value: -40, to: inMonth)!
        let earned: Set<Date> = [inMonth, earlier]
        #expect(StreakCalendar.earnedCount(inMonthOf: inMonth, earned: earned) == 1)
    }
}
