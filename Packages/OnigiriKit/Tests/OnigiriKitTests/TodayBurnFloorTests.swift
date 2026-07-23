import Foundation
import Testing
@testable import OnigiriKit

// Serialized: every test shares the two defaults keys, and the cleanup
// defers would race under parallel execution (the DeficitTargetHistory
// pattern).
@Suite(.serialized)
struct TodayBurnFloorTests {
    private static let cal = Calendar(identifier: .gregorian)
    private static let now = cal.date(
        from: DateComponents(year: 2026, month: 7, day: 22, hour: 21)
    )!

    private func cleanUp() {
        SharedStore.defaults.removeObject(forKey: TodayBurnFloor.dayKey)
        SharedStore.defaults.removeObject(forKey: TodayBurnFloor.kcalKey)
    }

    @Test func risesAndHoldsWithinADay() {
        cleanUp()
        defer { cleanUp() }
        #expect(TodayBurnFloor.ratcheted(3021, now: Self.now, calendar: Self.cal) == 3021)
        // Health reconciles double-counted watch↔phone samples downward
        // — the floor holds (the 2026-07-22 report's exact shape).
        #expect(TodayBurnFloor.ratcheted(2796, now: Self.now, calendar: Self.cal) == 3021)
        // Real accrual past the mark moves it again.
        #expect(TodayBurnFloor.ratcheted(3100, now: Self.now, calendar: Self.cal) == 3100)
    }

    @Test func resetsWithTheCalendarDay() {
        cleanUp()
        defer { cleanUp() }
        #expect(TodayBurnFloor.ratcheted(3021, now: Self.now, calendar: Self.cal) == 3021)
        let tomorrow = Self.cal.date(byAdding: .day, value: 1, to: Self.now)!
        #expect(TodayBurnFloor.ratcheted(150, now: tomorrow, calendar: Self.cal) == 150)
    }

    @Test func failedReadKeepsTheDaysMark() {
        cleanUp()
        defer { cleanUp() }
        #expect(TodayBurnFloor.ratcheted(2500, now: Self.now, calendar: Self.cal) == 2500)
        // A zero read (Health momentarily unavailable) must not
        // collapse the budget floor.
        #expect(TodayBurnFloor.ratcheted(0, now: Self.now, calendar: Self.cal) == 2500)
    }

    @Test func zeroOnAFreshDayStoresNothing() {
        cleanUp()
        defer { cleanUp() }
        #expect(TodayBurnFloor.ratcheted(0, now: Self.now, calendar: Self.cal) == 0)
        #expect(SharedStore.defaults.string(forKey: TodayBurnFloor.dayKey) == nil)
    }
}
