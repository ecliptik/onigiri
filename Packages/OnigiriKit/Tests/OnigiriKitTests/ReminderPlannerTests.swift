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

    @Test func waterCheckpointsOnlyWhereBehindPace() {
        // 30 of 64 oz at 8 AM: past 1/3 of goal (21.3), so 11 AM is
        // satisfied; behind 2/3 (42.7) and the full goal, so 3 PM and
        // 7 PM check in.
        let planned = ReminderPlanner.plan(
            state: .init(waterOz: 30, waterGoalOz: 64),
            enabled: .init(water: true),
            now: today(at: 8)
        )
        #expect(fireHours(planned, kind: .water) == [15, 19])
    }

    @Test func waterSilentOnceGoalMet() {
        let planned = ReminderPlanner.plan(
            state: .init(waterOz: 64, waterGoalOz: 64),
            enabled: .init(water: true),
            now: today(at: 8)
        )
        #expect(fireHours(planned, kind: .water).isEmpty)
    }

    @Test func waterOnlyPlansCheckpointsStillAhead() {
        let planned = ReminderPlanner.plan(
            state: .init(waterOz: 0, waterGoalOz: 64),
            enabled: .init(water: true),
            now: today(at: 16)
        )
        #expect(fireHours(planned, kind: .water) == [19])
        // Never for future days — water pacing is stateful.
        #expect(planned.filter { $0.kind == .water }.count == 1)
    }

    @Test func streakWarningWhenAliveAndUnmet() {
        let planned = ReminderPlanner.plan(
            state: .init(streak: 5, todayGoalMet: false),
            enabled: .init(streak: true),
            now: today(at: 8)
        )
        #expect(fireHours(planned, kind: .streak) == [20])
        #expect(planned.first { $0.kind == .streak }?.body.contains("5-day") == true)
        // Tomorrow is not pre-planned — today may end unearned.
        #expect(fireHours(planned, kind: .streak, dayOffset: 1).isEmpty)
    }

    @Test func streakWarningMovesToTomorrowOnceTodayIsEarned() {
        let planned = ReminderPlanner.plan(
            state: .init(streak: 6, todayGoalMet: true),
            enabled: .init(streak: true),
            now: today(at: 8)
        )
        #expect(fireHours(planned, kind: .streak).isEmpty)
        #expect(fireHours(planned, kind: .streak, dayOffset: 1) == [20])
        // By the time tomorrow's warning fires, the earned today has
        // joined the streak: 6 + today = "7-day streak".
        let tomorrow = planned.first { $0.kind == .streak }
        #expect(tomorrow?.body.contains("7-day streak") == true)
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
            state: .init(waterOz: 0, waterGoalOz: 64, streak: 3),
            enabled: .init(meals: true, water: true, streak: true),
            now: today(at: 7)
        )
        #expect(planned.map(\.fireDate) == planned.map(\.fireDate).sorted())
        #expect(Set(planned.map(\.id)).count == planned.count)
    }
}
