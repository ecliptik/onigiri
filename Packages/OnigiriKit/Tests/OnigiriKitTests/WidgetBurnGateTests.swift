import Testing
import Foundation
@testable import OnigiriKit

/// The health-check audit's coverage gap: this file's day-keyed storage
/// and midnight-rollover logic had zero tests — the exact shape of bug
/// this whole gate exists to prevent has already bitten a SIBLING
/// day-keyed type once (`TodayBurnFloor`, per this file's own doc
/// comment on why it copies that pattern).
///
/// Serialized: every test shares `SharedStore.defaults` keys.
@Suite(.serialized)
struct WidgetBurnGateTests {
    init() {
        let defaults = SharedStore.defaults
        for key in [
            WidgetBurnGate.renderedDayKey, WidgetBurnGate.renderedKcalKey,
            WidgetBurnGate.lastReloadKey, WidgetBurnGate.activityKey,
            WidgetBurnGate.journalKey, WidgetBurnGate.planJournalKey,
            WatchSync.lastLogAtKey,
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    @Test func nothingRenderedYetReadsAsNil() {
        #expect(WidgetBurnGate.renderedActiveKcal() == nil)
    }

    @Test func aRenderedMarkRoundTripsOnTheSameDay() {
        let now = Date.now
        WidgetBurnGate.recordRendered(activeKcal: 340, now: now)
        #expect(WidgetBurnGate.renderedActiveKcal(now: now) == 340)
    }

    /// The core behavior this gate is day-keyed FOR: a mark from a
    /// PRIOR day must not answer for today, or a stale mark would read
    /// as a huge negative delta and gate the whole morning's reload off.
    @Test func aMarkFromYesterdayDoesNotAnswerForToday() {
        let calendar = Calendar.current
        let today = Date.now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        WidgetBurnGate.recordRendered(activeKcal: 900, now: yesterday, calendar: calendar)
        #expect(WidgetBurnGate.renderedActiveKcal(now: yesterday, calendar: calendar) == 900)
        #expect(
            WidgetBurnGate.renderedActiveKcal(now: today, calendar: calendar) == nil,
            "yesterday's mark must not leak across midnight"
        )
    }

    @Test func reRenderingTheSameDayOverwritesTheMark() {
        let now = Date.now
        WidgetBurnGate.recordRendered(activeKcal: 200, now: now)
        WidgetBurnGate.recordRendered(activeKcal: 450, now: now)
        #expect(WidgetBurnGate.renderedActiveKcal(now: now) == 450)
    }

    @Test func journalStartsEmptyAndAppendsOneLinePerNote() {
        #expect(WidgetBurnGate.journal().isEmpty)
        WidgetBurnGate.note(activeKcal: 100, lastRendered: nil, reloading: false)
        WidgetBurnGate.note(activeKcal: 150, lastRendered: 100, reloading: true)
        #expect(WidgetBurnGate.journal().count == 2)
        #expect(WidgetBurnGate.journal().last?.contains("RELOAD") == true)
        #expect(WidgetBurnGate.journal().first?.contains("RELOAD") == false)
    }

    @Test func journalCapsAtFortyEntriesDroppingTheOldestFirst() {
        for i in 0..<45 {
            WidgetBurnGate.note(activeKcal: Double(i), lastRendered: nil, reloading: false)
        }
        let journal = WidgetBurnGate.journal()
        #expect(journal.count == 40)
        // The oldest 5 (active=0...4) must be the ones dropped.
        #expect(journal.first?.contains("active=5") == true)
        #expect(journal.last?.contains("active=44") == true)
    }

    @Test func planJournalRefreshesTheTimestampOnRepeatedValuesInsteadOfAppending() {
        WidgetBurnGate.notePlan(active: 100, restingMeasured: 1500, restingEstimate: nil, weight: 160)
        WidgetBurnGate.notePlan(active: 100, restingMeasured: 1500, restingEstimate: nil, weight: 160)
        #expect(WidgetBurnGate.planJournal().count == 1, "identical values must refresh the last row, not add a second one")

        WidgetBurnGate.notePlan(active: 120, restingMeasured: 1500, restingEstimate: nil, weight: 160)
        #expect(WidgetBurnGate.planJournal().count == 2, "a real change must add a new row")
    }

    @Test func burnReloadStampRoundTrips() {
        #expect(WidgetBurnGate.lastBurnReloadAt() == nil)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        WidgetBurnGate.noteBurnReload(at: now)
        #expect(WidgetBurnGate.lastBurnReloadAt() == now)
    }

    @Test func lastActivityAtPicksTheNewerOfBurnAndPhoneLog() {
        #expect(WidgetBurnGate.lastActivityAt() == nil)

        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_001_000)

        WidgetBurnGate.noteActivity(at: earlier)
        #expect(WidgetBurnGate.lastActivityAt() == earlier)

        WatchSync.stampPhoneLog(at: later)
        #expect(WidgetBurnGate.lastActivityAt() == later, "the newer of the two stamps must win")

        // And the reverse order — burn newer than the phone log.
        let latest = Date(timeIntervalSince1970: 1_700_002_000)
        WidgetBurnGate.noteActivity(at: latest)
        #expect(WidgetBurnGate.lastActivityAt() == latest)
    }
}
