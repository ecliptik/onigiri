import Foundation
import Testing
@testable import OnigiriKit

/// The phone→watch plan-input handoff: which burn/weight the watch's plan
/// uses (synced-while-fresh vs local), and how the complication providers
/// pace their poll after a phone log stamp. Both devices' budgets diverged
/// because the watch's purged Health history skewed its own 14-day average
/// — these pin the preference rules that closed that gap.
struct PlanInputSyncTests {
    private static let cal = Calendar(identifier: .gregorian)
    private static let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 12))!

    private static func day(_ offset: Int) -> String {
        DeficitTargetHistory.dayKey(
            for: cal.date(byAdding: .day, value: offset, to: now)!, calendar: cal
        )
    }

    @Test func freshSyncedInputWinsOverLocal() {
        let resolved = DailyPlanLoader.planInput(
            synced: (2750, Self.day(0)), local: 2400, calendar: Self.cal, now: Self.now
        )
        #expect(resolved == 2750)
    }

    @Test func yesterdaysSyncedInputStillWins() {
        // The phone re-stamps on every foreground; a day-old push (phone
        // not opened since last night) is still its full-history number.
        let resolved = DailyPlanLoader.planInput(
            synced: (2750, Self.day(-1)), local: 2400, calendar: Self.cal, now: Self.now
        )
        #expect(resolved == 2750)
    }

    @Test func staleSyncedInputFallsBackToLocal() {
        // Two days without contact: trust the watch's own store over a
        // stale phone snapshot.
        let resolved = DailyPlanLoader.planInput(
            synced: (2750, Self.day(-2)), local: 2400, calendar: Self.cal, now: Self.now
        )
        #expect(resolved == 2400)
    }

    @Test func noSyncedInputMeansLocal() {
        let resolved = DailyPlanLoader.planInput(
            synced: nil, local: 2400, calendar: Self.cal, now: Self.now
        )
        #expect(resolved == 2400)
    }

    @Test func freshSyncedInputCoversAMissingLocal() {
        // A watch whose own store answers nothing (fresh pair, purge)
        // still gets the phone's number.
        let resolved = DailyPlanLoader.planInput(
            synced: (2750, Self.day(0)), local: nil, calendar: Self.cal, now: Self.now
        )
        #expect(resolved == 2750)
    }

    @Test func staleSyncedWithNoLocalMeansNone() {
        let resolved = DailyPlanLoader.planInput(
            synced: (2750, Self.day(-3)), local: nil, calendar: Self.cal, now: Self.now
        )
        #expect(resolved == nil)
    }

    // MARK: - Post-log poll pacing

    @Test func recentLogStampShortensThePoll() {
        let logged = Self.now.addingTimeInterval(-5 * 60)
        #expect(
            WidgetRefreshPolicy.nextPoll(now: Self.now, lastLogAt: logged)
                == WidgetRefreshPolicy.postLogPoll
        )
    }

    @Test func agedLogStampReturnsToTheHourlyFallback() {
        let logged = Self.now.addingTimeInterval(-WidgetRefreshPolicy.postLogWindow - 1)
        #expect(
            WidgetRefreshPolicy.nextPoll(now: Self.now, lastLogAt: logged)
                == WidgetRefreshPolicy.pollFallback
        )
    }

    @Test func noStampMeansTheFallback() {
        #expect(
            WidgetRefreshPolicy.nextPoll(now: Self.now, lastLogAt: nil)
                == WidgetRefreshPolicy.pollFallback
        )
    }

    @Test func clockSkewedFutureStampStillCountsAsRecent() {
        // A phone clock a minute ahead must not turn a just-synced stamp
        // into "stale for the next hour".
        let skewed = Self.now.addingTimeInterval(60)
        #expect(
            WidgetRefreshPolicy.nextPoll(now: Self.now, lastLogAt: skewed)
                == WidgetRefreshPolicy.postLogPoll
        )
    }
}
