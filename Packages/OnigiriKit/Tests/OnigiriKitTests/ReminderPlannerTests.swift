import Foundation
import Testing
@testable import OnigiriKit

struct ReminderPlannerTests {
    private let calendar = Calendar.current

    /// A fixed "now" at the given hour today.
    private func today(at hour: Int, minute: Int = 0) -> Date {
        calendar.date(
            bySettingHour: hour, minute: minute, second: 0,
            of: calendar.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        )!
    }

    private func fireHours(_ planned: [PlannedReminder], kind: PlannedReminder.Kind, dayOffset: Int = 0) -> [Int] {
        let dayStart = calendar.startOfDay(for: today(at: 0))
        return planned
            .filter { $0.kind == kind }
            .filter {
                calendar.dateComponents(
                    [.day], from: dayStart, to: calendar.startOfDay(for: $0.fireDate)
                ).day == dayOffset
            }
            .map { calendar.component(.hour, from: $0.fireDate) }
    }

    @Test func nothingPlannedWhenEverythingDisabled() {
        let planned = ReminderPlanner.plan(
            state: .init(), enabled: .init(), now: today(at: 8)
        )
        #expect(planned.isEmpty)
    }

    @Test func mealNudgeAt2pmWhenNothingLogged() {
        let planned = ReminderPlanner.plan(
            state: .init(hasLoggedFood: false),
            enabled: .init(meals: true),
            now: today(at: 8)
        )
        #expect(fireHours(planned, kind: .meals) == [14])
    }

    @Test func mealNudgeSkippedOnceFoodIsLogged() {
        let planned = ReminderPlanner.plan(
            state: .init(hasLoggedFood: true),
            enabled: .init(meals: true),
            now: today(at: 8)
        )
        #expect(fireHours(planned, kind: .meals).isEmpty)
        // Future days still get their nudges — state there is unknown.
        #expect(fireHours(planned, kind: .meals, dayOffset: 1) == [14])
        #expect(fireHours(planned, kind: .meals, dayOffset: 3) == [14])
    }

    @Test func mealNudgeSkippedWhenPlanningAfter2pm() {
        let planned = ReminderPlanner.plan(
            state: .init(hasLoggedFood: false),
            enabled: .init(meals: true),
            now: today(at: 15)
        )
        #expect(fireHours(planned, kind: .meals).isEmpty)
    }

    @Test func waterChecksInOnADayWithNothingLogged() {
        let planned = ReminderPlanner.plan(
            state: .init(waterOz: 0),
            enabled: .init(water: true),
            now: today(at: 8)
        )
        #expect(fireHours(planned, kind: .water) == [11, 15, 19])
    }

    /// The 2026-08-17 report: 24 oz logged on the watch in the morning,
    /// and the 11 AM check-in still read "You're at 0 of 64 oz."
    /// ANY water silences every remaining check-in — the gate is
    /// "nothing logged", not a pace, precisely because a pace is what a
    /// stale snapshot gets wrong.
    @Test func anyWaterAtAllSilencesTheDay() {
        for logged in [1.0, 8.0, 24.0, 200.0] {
            let planned = ReminderPlanner.plan(
                state: .init(waterOz: logged),
                enabled: .init(water: true),
                now: today(at: 8)
            )
            #expect(fireHours(planned, kind: .water).isEmpty)
        }
    }

    @Test func waterOnlyPlansCheckpointsStillAhead() {
        let planned = ReminderPlanner.plan(
            state: .init(waterOz: 0),
            enabled: .init(water: true),
            now: today(at: 16)
        )
        #expect(fireHours(planned, kind: .water) == [19])
        // Never for future days — tomorrow's water state is unknowable.
        #expect(planned.filter { $0.kind == .water }.count == 1)
    }

    /// Layer 1 of `plans/PLAN-reminders.md`: a body is delivered exactly
    /// as it was written hours earlier, so it may not assert anything
    /// that can change in between. A digit is the tell — every figure
    /// these used to carry (water progress, the streak's day count) was
    /// live state.
    @Test func noReminderBodyCarriesALiveFigure() {
        let planned = ReminderPlanner.plan(
            state: .init(hasLoggedFood: false, waterOz: 0, streak: 5),
            enabled: .init(meals: true, water: true, streak: true),
            now: today(at: 7)
        )
        #expect(!planned.isEmpty)
        for reminder in planned {
            let hasDigit = (reminder.title + reminder.body).contains { $0.isNumber }
            #expect(hasDigit == false, "\(reminder.title) / \(reminder.body)")
        }
    }

    @Test func streakWarningWhenNothingLoggedYet() {
        let planned = ReminderPlanner.plan(
            state: .init(hasLoggedFood: false, streak: 5),
            enabled: .init(streak: true),
            now: today(at: 8)
        )
        #expect(fireHours(planned, kind: .streak) == [20])
        // Tomorrow is not pre-planned — today may end unearned.
        #expect(fireHours(planned, kind: .streak, dayOffset: 1).isEmpty)
    }

    @Test func noStreakWarningOnceAnythingIsLogged() {
        // The 2026-07-22 report: logged all day but the goal not YET met
        // at the 8 PM check (burn still accruing) fired the warning
        // every evening. Logging anything silences it — the warning is
        // "you forgot to log", not "you're over budget".
        let planned = ReminderPlanner.plan(
            state: .init(hasLoggedFood: true, streak: 5, todayGoalMet: false),
            enabled: .init(streak: true),
            now: today(at: 8)
        )
        #expect(planned.filter { $0.kind == .streak }.isEmpty)
    }

    @Test func streakWarningMovesToTomorrowOnceTodayIsEarned() {
        // An earned day is by definition a logged day (isTracked gates
        // the badge) — the synthetic state says both.
        let planned = ReminderPlanner.plan(
            state: .init(hasLoggedFood: true, streak: 6, todayGoalMet: true),
            enabled: .init(streak: true),
            now: today(at: 8)
        )
        #expect(fireHours(planned, kind: .streak).isEmpty)
        #expect(fireHours(planned, kind: .streak, dayOffset: 1) == [20])
    }

    @Test func noStreakWarningForShortStreaks() {
        let planned = ReminderPlanner.plan(
            state: .init(streak: 1, todayGoalMet: false),
            enabled: .init(streak: true),
            now: today(at: 8)
        )
        #expect(planned.filter { $0.kind == .streak }.isEmpty)
    }

    @Test func plansAreSortedAndIdsUnique() {
        let planned = ReminderPlanner.plan(
            state: .init(waterOz: 0, streak: 3),
            enabled: .init(meals: true, water: true, streak: true),
            now: today(at: 7)
        )
        #expect(planned.map(\.fireDate) == planned.map(\.fireDate).sorted())
        #expect(Set(planned.map(\.id)).count == planned.count)
    }

    // The 13 tests above all ride the default `times:` — they pin that an
    // untouched install keeps the original 2 PM / 11-3-7 / 8 PM schedule.

    @Test func customTimesMoveTheSchedule() {
        // Meal at 10:30 AM, streak at 9:15 PM — minute precision included.
        let times = ReminderPlanner.Times(
            mealMinute: 10 * 60 + 30, streakMinute: 21 * 60 + 15
        )
        let planned = ReminderPlanner.plan(
            state: .init(streak: 4),
            enabled: .init(meals: true, streak: true),
            times: times, now: today(at: 8)
        )
        let meal = planned.first { $0.kind == .meals }
        #expect(meal.map { calendar.component(.hour, from: $0.fireDate) } == 10)
        #expect(meal.map { calendar.component(.minute, from: $0.fireDate) } == 30)
        let streak = planned.first { $0.kind == .streak }
        #expect(streak.map { calendar.component(.hour, from: $0.fireDate) } == 21)
        #expect(streak.map { calendar.component(.minute, from: $0.fireDate) } == 15)
        // The horizon nudges follow the moved meal time too.
        #expect(fireHours(planned, kind: .meals, dayOffset: 2) == [10])
    }

    @Test func customWaterTimesMoveTheCheckIns() {
        // Entered out of order; the plan comes back chronological.
        let times = ReminderPlanner.Times(waterMinutes: [19 * 60, 13 * 60, 9 * 60])
        let planned = ReminderPlanner.plan(
            state: .init(waterOz: 0),
            enabled: .init(water: true),
            times: times, now: today(at: 6)
        )
        #expect(fireHours(planned, kind: .water) == [9, 13, 19])
    }

    @Test func duplicateWaterTimesCollapse() {
        // Two check-ins on the same minute are one notification, not two
        // stacked at 3 PM.
        let times = ReminderPlanner.Times(waterMinutes: [15 * 60, 15 * 60, 19 * 60])
        let planned = ReminderPlanner.plan(
            state: .init(waterOz: 0),
            enabled: .init(water: true),
            times: times, now: today(at: 8)
        )
        #expect(fireHours(planned, kind: .water) == [15, 19])
        #expect(planned.filter { $0.kind == .water }.count == 2)
    }
}
