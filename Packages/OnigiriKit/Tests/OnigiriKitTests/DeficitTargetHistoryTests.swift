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

    /// The one shared judging rule (Today's goal card AND the
    /// Calendar's day card call this): TODAY is judged by the live
    /// target even when a snapshot exists — a stale stamp must not
    /// outrank a goal the user just edited — while history keeps the
    /// bar it was actually held to, falling back to live only when
    /// unstamped (audit, 2026-08-17: the two surfaces carried separate
    /// copies of this rule and disagreed about the day in progress).
    @Test func todayIsJudgedLiveHistoryByItsSnapshot() {
        defer { SharedStore.defaults.removeObject(forKey: DeficitTargetHistory.key) }
        let calendar = Calendar.current
        let now = Date.now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let unstamped = calendar.date(from: DateComponents(year: 2014, month: 4, day: 4))!

        DeficitTargetHistory.recordToday(targetKcal: 500, now: now, calendar: calendar)
        DeficitTargetHistory.recordToday(targetKcal: 640, now: yesterday, calendar: calendar)

        // The goal edit moved the live target to 320; today's stale 500
        // stamp loses to it.
        #expect(DeficitTargetHistory.judgingTarget(
            on: now, live: 320, now: now, calendar: calendar) == 320)
        // Yesterday keeps its own stamp.
        #expect(DeficitTargetHistory.judgingTarget(
            on: yesterday, live: 320, now: now, calendar: calendar) == 640)
        // Pre-snapshot history falls back to the live target.
        #expect(DeficitTargetHistory.judgingTarget(
            on: unstamped, live: 320, now: now, calendar: calendar) == 320)
        // A goal-less live plan judges today as nil, stamp or no stamp.
        #expect(DeficitTargetHistory.judgingTarget(
            on: now, live: nil, now: now, calendar: calendar) == nil)
    }

    // MARK: - What the loader is allowed to write here
    //
    // These drive `DailyPlanLoader.load`, not `recordToday`, but they
    // live in THIS suite deliberately: they assert on the one defaults
    // key every test above shares, and only a serialized suite can do
    // that without racing its own cleanup.

    #if canImport(HealthKit)
    /// A weight goal 100 days out and 20 lb to go: 20 × 3500 / 100.
    private static func loseGoal(now: Date, calendar: Calendar) -> SyncedGoal {
        SyncedGoal(
            targetWeightLb: 190,
            targetDate: calendar.date(byAdding: .day, value: 100, to: now)!,
            // nil, as on the device where D1 was confirmed — with a
            // fallback the sealed read borrows it and never reaches 0.
            fallbackCurrentWeightLb: nil
        )
    }

    /// Today's key only. The plan-weight cache is NOT touched here —
    /// two other suites own that key and clearing it from this one
    /// would break them (and them, this one) under parallel execution.
    /// The stub carries its own day stamp instead.
    private func clearStamps() {
        SharedStore.defaults.removeObject(forKey: DeficitTargetHistory.key)
    }

    /// D1 (2026-08-18): a SEALED store answers a weight goal with a nil
    /// target, which used to be stamped as 0 — `DayBadgeRule.anyDeficit`,
    /// "any deficit earns the badge". "The last value recorded on a day
    /// stands", so one sealed load at 23:50 permanently re-graded the
    /// day to a laxer rule, silently. Five such reads were in the
    /// device's own journal across two days.
    @MainActor
    @Test func aSealedReadCannotOverwriteAGoodStamp() async {
        clearStamps()
        defer { clearStamps() }
        let calendar = Calendar.current
        let now = Date.now
        let today = DeficitTargetHistory.dayKey(for: now, calendar: calendar)
        let goal = Self.loseGoal(now: now, calendar: calendar)

        // A healthy read stamps the real target: 20 lb over 100 days.
        _ = await DailyPlanLoader.load(
            goal: goal,
            health: StubPlanHealth(weightLb: 210, lastGoodDay: today))
        #expect(DeficitTargetHistory.target(on: now, calendar: calendar) == 700)

        // Then the store seals: every channel empty, weight nil, while
        // the cache still vouches for a weight read moments ago.
        _ = await DailyPlanLoader.load(
            goal: goal,
            health: StubPlanHealth(weightLb: nil, lastGoodDay: today))
        #expect(DeficitTargetHistory.target(on: now, calendar: calendar) == 700)
    }

    /// The other half of the line: a user who genuinely has no weigh-ins
    /// has no target, and that is real information the day must keep.
    /// Nothing cached ⇒ the nil is believed ⇒ the stamp happens.
    @MainActor
    @Test func aUserWithNoWeighInsStillStamps() async {
        clearStamps()
        defer { clearStamps() }
        let calendar = Calendar.current
        let now = Date.now

        // Nothing ever cached: the nil weight is honest, and must be
        // believed exactly as it was before the guard existed.
        _ = await DailyPlanLoader.load(
            goal: Self.loseGoal(now: now, calendar: calendar),
            health: StubPlanHealth(weightLb: nil, lastGoodDay: nil))
        #expect(DeficitTargetHistory.hasSnapshot(on: now, calendar: calendar))
        #expect(DeficitTargetHistory.target(on: now, calendar: calendar) == 0)
    }

    /// And a MAINTENANCE day stamps its sentinel through a sealed read:
    /// that value is read off the goal, not off Health, so withholding
    /// the store can't change what gets written.
    @MainActor
    @Test func maintenanceStampsEvenThroughASealedRead() async {
        clearStamps()
        defer { clearStamps() }
        let calendar = Calendar.current
        let now = Date.now
        let today = DeficitTargetHistory.dayKey(for: now, calendar: calendar)

        _ = await DailyPlanLoader.load(
            goal: SyncedGoal(
                targetWeightLb: 200, targetDate: now,
                fallbackCurrentWeightLb: nil, mode: GoalMode.maintain),
            health: StubPlanHealth(weightLb: nil, lastGoodDay: today))
        #expect(DeficitTargetHistory.hasSnapshot(on: now, calendar: calendar))
        #expect(
            DeficitTargetHistory.rulesByDay(calendar: calendar)[calendar.startOfDay(for: now)]
                == .maintenanceBand
        )
    }
    #endif
}

#if canImport(HealthKit)
/// The loader's whole read surface, stubbed. `weightLb: nil` IS the
/// sealed signature — the store is allowed to answer empty rather than
/// throw, which is why `HealthReadTrust` judges the result instead of
/// probing the store (see its doc comment).
@MainActor
private struct StubPlanHealth: HealthPlanReading {
    let weightLb: Double?
    /// Day stamp on the last weight the store answered with — supplied
    /// here rather than through the real App Group cache, which two
    /// other suites clear concurrently.
    let lastGoodDay: String?
    var summary: DailyEnergySummary = .zero

    func todaySummary() async throws -> DailyEnergySummary { summary }
    func latestBodyMassLb() async throws -> Double? { weightLb }
    func bodyProfile() async -> (heightCm: Double?, ageYears: Int?, sex: BasalEstimate.Sex) {
        (nil, nil, .unspecified)
    }
    func lastGoodWeightDay() -> String? { lastGoodDay }
}
#endif
