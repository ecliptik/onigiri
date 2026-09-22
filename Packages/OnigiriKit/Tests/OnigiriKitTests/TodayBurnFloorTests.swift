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
    /// The on-device boundary the straddle tests reproduce.
    private static let lateOnThe19th = cal.date(
        from: DateComponents(year: 2026, month: 9, day: 19, hour: 23, minute: 59)
    )!
    private static let justAfterMidnight = cal.date(
        from: DateComponents(year: 2026, month: 9, day: 20, hour: 0, minute: 1)
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

    /// A read that began before midnight and landed after it carries the
    /// FINISHED day's burn. Recording it under the new day's key floors
    /// the whole of the next day at yesterday's total — measured on
    /// device 2026-09-20, with the phone's own plan journal showing the
    /// 19th's finished totals stamped at `09-20 00:01`.
    @Test func aReadThatStraddledMidnightRecordsNothing() {
        cleanUp()
        defer { cleanUp() }
        // Yesterday's finished burn, handed over one minute into today.
        #expect(
            TodayBurnFloor.ratcheted(
                2400, readAt: Self.lateOnThe19th, now: Self.justAfterMidnight,
                calendar: Self.cal
            ) == 2400
        )
        // Nothing persisted — which is the whole point. A returned value
        // is one frame; a stored mark is the rest of the day.
        #expect(SharedStore.defaults.string(forKey: TodayBurnFloor.dayKey) == nil)
        // …so the day's first clean read sets the real floor, instead of
        // being held under a number it can never reach.
        #expect(
            TodayBurnFloor.ratcheted(
                2000, readAt: Self.justAfterMidnight, now: Self.justAfterMidnight,
                calendar: Self.cal
            ) == 2000
        )
    }

    /// The shipped behavior this replaces, kept as the regression's
    /// shape: with no read stamp the straddling value wins and every
    /// later read of the day is floored at it. This is the 2026-09-20
    /// phone/watch gap, in two lines.
    @Test func withoutAReadStampTheStraddlingValueStillWins() {
        cleanUp()
        defer { cleanUp() }
        #expect(
            TodayBurnFloor.ratcheted(2400, now: Self.justAfterMidnight, calendar: Self.cal)
                == 2400
        )
        #expect(
            TodayBurnFloor.ratcheted(2000, now: Self.justAfterMidnight, calendar: Self.cal)
                == 2400
        )
    }

    /// The guard must be invisible to an ordinary read — it fires on the
    /// day boundary and nowhere else.
    @Test func aReadInsideOneDayRatchetsNormally() {
        cleanUp()
        defer { cleanUp() }
        let readAt = Self.cal.date(byAdding: .minute, value: -2, to: Self.now)!
        #expect(
            TodayBurnFloor.ratcheted(3021, readAt: readAt, now: Self.now, calendar: Self.cal)
                == 3021
        )
        #expect(
            TodayBurnFloor.ratcheted(2796, readAt: readAt, now: Self.now, calendar: Self.cal)
                == 3021
        )
    }

    /// The read half must not write — `DailyPlanLoader.diagnose` prints
    /// the budget's inputs and must not move the budget doing it.
    @Test func readingTheMarkRecordsNothing() {
        cleanUp()
        defer { cleanUp() }
        #expect(TodayBurnFloor.todayMark(now: Self.now, calendar: Self.cal) == 0)
        #expect(SharedStore.defaults.string(forKey: TodayBurnFloor.dayKey) == nil)
        _ = TodayBurnFloor.ratcheted(2500, now: Self.now, calendar: Self.cal)
        #expect(TodayBurnFloor.todayMark(now: Self.now, calendar: Self.cal) == 2500)
        // A mark belongs to its day and no other.
        let tomorrow = Self.cal.date(byAdding: .day, value: 1, to: Self.now)!
        #expect(TodayBurnFloor.todayMark(now: tomorrow, calendar: Self.cal) == 0)
    }

    /// The recovery the `readAt` guard cannot provide: a mark already
    /// written runs to midnight, because the ratchet only rises.
    @Test func clearingDropsTheMarkSoTheNextReadSetsItAfresh() {
        cleanUp()
        defer { cleanUp() }
        #expect(TodayBurnFloor.ratcheted(2400, now: Self.now, calendar: Self.cal) == 2400)
        // Today's real burn cannot get out from under it.
        #expect(TodayBurnFloor.ratcheted(2020, now: Self.now, calendar: Self.cal) == 2400)
        #expect(TodayBurnFloor.clearTodayIfRequested(arguments: ["--clear-burn-floor"]))
        #expect(TodayBurnFloor.ratcheted(2020, now: Self.now, calendar: Self.cal) == 2020)
    }

    @Test func clearingNeedsTheArgument() {
        cleanUp()
        defer { cleanUp() }
        #expect(TodayBurnFloor.ratcheted(2400, now: Self.now, calendar: Self.cal) == 2400)
        #expect(!TodayBurnFloor.clearTodayIfRequested(arguments: ["--seed-sample-data"]))
        #expect(TodayBurnFloor.todayMark(now: Self.now, calendar: Self.cal) == 2400)
    }

    @Test func zeroOnAFreshDayStoresNothing() {
        cleanUp()
        defer { cleanUp() }
        #expect(TodayBurnFloor.ratcheted(0, now: Self.now, calendar: Self.cal) == 0)
        #expect(SharedStore.defaults.string(forKey: TodayBurnFloor.dayKey) == nil)
    }
}
