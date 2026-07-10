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
        let earned = StreakCalendar.earnedDays(totals: history, targetDeficitKcal: 600)
        #expect(earned == [day(-3)])
    }

    @Test func anyDeficitEarnsWithoutGoal() {
        let history = [
            totals(-2, intake: 1500, burn: 1600),  // deficit 100 → earned
            totals(-1, intake: 1700, burn: 1600),  // surplus → no
        ]
        let earned = StreakCalendar.earnedDays(totals: history, targetDeficitKcal: nil)
        #expect(earned == [day(-2)])
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
