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

    // MARK: - Recent-activity poll pacing

    /// Was "post-log" until 2026-08-03: burn opens this window now too,
    /// which is the whole point — a walk with no logging used to leave
    /// every complication on the flat hourly fallback.
    @Test func recentActivityStampShortensThePoll() {
        let stamped = Self.now.addingTimeInterval(-5 * 60)
        #expect(
            WidgetRefreshPolicy.nextPoll(
                now: Self.now, lastActivityAt: stamped, calendar: Self.cal
            ) == WidgetRefreshPolicy.recentActivityPoll
        )
    }

    @Test func agedStampReturnsToTheBaselineCadence() {
        let stamped = Self.now.addingTimeInterval(-WidgetRefreshPolicy.recentActivityWindow - 1)
        #expect(
            WidgetRefreshPolicy.nextPoll(
                now: Self.now, lastActivityAt: stamped, calendar: Self.cal
            ) == WidgetRefreshPolicy.wakingPoll
        )
    }

    @Test func noStampMeansTheBaselineCadence() {
        #expect(
            WidgetRefreshPolicy.nextPoll(
                now: Self.now, lastActivityAt: nil, calendar: Self.cal
            ) == WidgetRefreshPolicy.wakingPoll
        )
    }

    @Test func clockSkewedFutureStampStillCountsAsRecent() {
        // A phone clock a minute ahead must not turn a just-synced stamp
        // into "stale for the next hour".
        let skewed = Self.now.addingTimeInterval(60)
        #expect(
            WidgetRefreshPolicy.nextPoll(
                now: Self.now, lastActivityAt: skewed, calendar: Self.cal
            ) == WidgetRefreshPolicy.recentActivityPoll
        )
    }

    // MARK: - Waking-hours cadence

    @Test func middayPollsOnTheWakingCadence() {
        #expect(
            WidgetRefreshPolicy.pollInterval(now: Self.now, calendar: Self.cal)
                == WidgetRefreshPolicy.wakingPoll
        )
    }

    @Test func overnightPollsFarLessOften() {
        // 03:00 — nothing is moving, and the budget spent here is budget
        // not available at lunchtime.
        let night = Self.cal.date(
            from: DateComponents(year: 2026, month: 7, day: 20, hour: 3)
        )!
        #expect(
            WidgetRefreshPolicy.pollInterval(now: night, calendar: Self.cal)
                == WidgetRefreshPolicy.sleepingPoll
        )
    }

    @Test func theWakingWindowIsHalfOpen() {
        func hour(_ h: Int) -> Date {
            Self.cal.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: h))!
        }
        // 07:00 is in, 23:00 is out — the boundary the constants name.
        #expect(WidgetRefreshPolicy.isWakingHour(hour(7), calendar: Self.cal))
        #expect(WidgetRefreshPolicy.isWakingHour(hour(22), calendar: Self.cal))
        #expect(!WidgetRefreshPolicy.isWakingHour(hour(23), calendar: Self.cal))
        #expect(!WidgetRefreshPolicy.isWakingHour(hour(6), calendar: Self.cal))
    }

    // MARK: - Burn gate

    /// The gate exists because WidgetKit grants ~40–70 reloads a day and
    /// active energy changes constantly: reload on every sample and the
    /// widget freezes by mid-afternoon, which is worse than the staleness
    /// it was meant to fix.

    @Test func aBigEnoughRiseSpendsAReload() {
        #expect(WidgetRefreshPolicy.shouldReloadForBurn(
            activeKcal: 250,
            lastRenderedActiveKcal: 200,
            lastReloadAt: Self.now.addingTimeInterval(-30 * 60),
            now: Self.now
        ))
    }

    @Test func aTrickleDoesNot() {
        #expect(!WidgetRefreshPolicy.shouldReloadForBurn(
            activeKcal: 210,
            lastRenderedActiveKcal: 200,
            lastReloadAt: Self.now.addingTimeInterval(-30 * 60),
            now: Self.now
        ))
    }

    @Test func aRecentReloadBlocksEvenALargeRise() {
        // The floor between reloads holds regardless of delta — a
        // workout that lands 400 kcal in one batch must not fire the
        // gate repeatedly as its samples arrive.
        #expect(!WidgetRefreshPolicy.shouldReloadForBurn(
            activeKcal: 600,
            lastRenderedActiveKcal: 200,
            lastReloadAt: Self.now.addingTimeInterval(-60),
            now: Self.now
        ))
    }

    @Test func noBaselineReloadsOnce() {
        // Nothing rendered today yet (fresh day, fresh install): reload,
        // rather than wait out a delta there is no baseline to measure.
        #expect(WidgetRefreshPolicy.shouldReloadForBurn(
            activeKcal: 12,
            lastRenderedActiveKcal: nil,
            lastReloadAt: nil,
            now: Self.now
        ))
    }

    @Test func aFallingTotalNeverReloads() {
        // Health revises today's burn downward when the watch's samples
        // reconcile with the phone's estimates (the TodayBurnFloor
        // lesson). A drop is not news.
        #expect(!WidgetRefreshPolicy.shouldReloadForBurn(
            activeKcal: 150,
            lastRenderedActiveKcal: 200,
            lastReloadAt: nil,
            now: Self.now
        ))
    }
}
