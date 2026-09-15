import Foundation
import Testing
@testable import OnigiriKit

/// Split out of `PlanInputSyncTests` (health-check audit, 2026-09-14) —
/// that file's name and doc comment are about the phone→watch plan-input
/// handoff specifically, and two-thirds of its tests were actually about
/// this unrelated type: how often the widget/complication providers poll,
/// and when a burn change actually spends a reload.
struct WidgetRefreshPolicyTests {
    private static let cal = Calendar(identifier: .gregorian)
    private static let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 12))!

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
