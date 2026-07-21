import Testing
import Foundation
@testable import OnigiriKit

// Serialized: every test shares one defaults key, and the cleanup
// defers would race under parallel execution.
@Suite(.serialized)
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

        let byDay = DeficitTargetHistory.rulesByDay(calendar: calendar)
        #expect(byDay[calendar.startOfDay(for: now)] == .anyDeficit)
    }

    @Test func maintenanceStampsTheBandRuleWithoutLeakingTheSentinel() {
        defer { SharedStore.defaults.removeObject(forKey: DeficitTargetHistory.key) }
        let calendar = Calendar.current
        let now = Date.now

        DeficitTargetHistory.recordToday(
            targetKcal: nil, isMaintenance: true, now: now, calendar: calendar
        )
        // The rule decodes at the boundary; target(on:) never shows -1.
        #expect(DeficitTargetHistory.target(on: now, calendar: calendar) == nil)
        #expect(DeficitTargetHistory.hasSnapshot(on: now, calendar: calendar))
        let byDay = DeficitTargetHistory.rulesByDay(calendar: calendar)
        #expect(byDay[calendar.startOfDay(for: now)] == .maintenanceBand)

        // A deficit-target stamp decodes back to its target and reads
        // through target(on:) unchanged.
        DeficitTargetHistory.recordToday(targetKcal: 620, now: now, calendar: calendar)
        #expect(DeficitTargetHistory.target(on: now, calendar: calendar) == 620)
        #expect(
            DeficitTargetHistory.rulesByDay(calendar: calendar)[calendar.startOfDay(for: now)]
                == .deficitTarget(620)
        )
    }

    @Test func hasSnapshotDistinguishesUnstampedDays() {
        // A distant fixed day: today's key is written concurrently by
        // any suite that loads a plan, so a negative assert on .now
        // is a race, not a test.
        SharedStore.defaults.removeObject(forKey: DeficitTargetHistory.key)
        defer { SharedStore.defaults.removeObject(forKey: DeficitTargetHistory.key) }
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2013, month: 3, day: 3))!
        #expect(!DeficitTargetHistory.hasSnapshot(on: day, calendar: calendar))
        DeficitTargetHistory.recordToday(targetKcal: nil, now: day, calendar: calendar)
        #expect(DeficitTargetHistory.hasSnapshot(on: day, calendar: calendar))
    }
}
