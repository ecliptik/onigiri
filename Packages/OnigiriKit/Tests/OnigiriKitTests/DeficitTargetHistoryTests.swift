import Testing
import Foundation
@testable import OnigiriKit

struct DeficitTargetHistoryTests {
    @Test func dayKeyRoundTrips() {
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12))!
        let key = DeficitTargetHistory.dayKey(for: day, calendar: calendar)
        #expect(key == "2026-07-12")
        #expect(DeficitTargetHistory.date(fromDayKey: key, calendar: calendar) == day)
    }

    @Test func recordsAndReadsBackTodaysTarget() {
        defer { SharedStore.defaults.removeObject(forKey: DeficitTargetHistory.key) }
        let calendar = Calendar.current
        let now = Date.now

        DeficitTargetHistory.recordToday(targetKcal: 550, now: now, calendar: calendar)
        #expect(DeficitTargetHistory.target(on: now, calendar: calendar) == 550)

        // Re-recording the same day overwrites (last value of the day wins).
        DeficitTargetHistory.recordToday(targetKcal: 480, now: now, calendar: calendar)
        #expect(DeficitTargetHistory.target(on: now, calendar: calendar) == 480)

        // nil (no goal) records 0 — the "any deficit" rule, distinct
        // from having no snapshot at all.
        DeficitTargetHistory.recordToday(targetKcal: nil, now: now, calendar: calendar)
        #expect(DeficitTargetHistory.target(on: now, calendar: calendar) == 0)

        let byDay = DeficitTargetHistory.targetsByDay(calendar: calendar)
        #expect(byDay[calendar.startOfDay(for: now)] == 0)
    }
}
