#if canImport(HealthKit)
import Foundation
import HealthKit

/// All HealthKit access for Onigiri. HealthKit is the log store: food energy,
/// sodium, and water are written as samples; energy burn and weight are read.
/// See plans/PLAN.md.
@MainActor
public final class HealthKitService {
    public static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store = HKHealthStore()
    private var isObservingLogChanges = false
    private var isObservingWeightChanges = false
    private var isObservingBurnChanges = false

    public init() {}

    // MARK: - Authorization

    private static let shareTypes: Set<HKSampleType> = {
        var types: Set<HKSampleType> = [
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietarySodium),
            HKQuantityType(.dietaryWater),
            HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietaryFatSaturated),
            HKQuantityType(.dietaryFatPolyunsaturated),
            HKQuantityType(.dietaryFatMonounsaturated),
            HKQuantityType(.dietaryCholesterol),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryFiber),
            HKQuantityType(.dietarySugar),
            HKQuantityType(.dietaryCaffeine),
        ]
        for micro in Micronutrient.allCases {
            types.insert(HKQuantityType(micro.healthKitIdentifier))
        }
        return types
    }()

    /// Read covers everything we write, plus burn and weight. A real
    /// device (unlike the simulator) strips never-requested-for-read
    /// sample types out of read-back correlations — the day detail came
    /// back with no macros/micros on hardware until read was requested.
    private static let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.bodyMass),
            // Read ONLY to estimate resting burn (BasalEstimate) — the
            // baseline every day's budget is built on, credited from
            // midnight — so it comes from Health instead of asking
            // someone to type their body into a form. Never written,
            // never logged, never leaves the device.
            HKQuantityType(.height),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
        ]
        for sample in shareTypes {
            types.insert(sample)
        }
        return types
    }()

    /// Whether the system would show the permission sheet if we asked.
    public func shouldRequestAuthorization() async throws -> Bool {
        let status = try await store.statusForAuthorizationRequest(
            toShare: Self.shareTypes, read: Self.readTypes
        )
        return status == .shouldRequest
    }

    public func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    /// Write access was explicitly denied. Read denial isn't detectable
    /// (by design), but write denial is — and it's what makes every log
    /// attempt fail, so Settings and Today surface a recovery hint.
    public func sharingDenied() -> Bool {
        store.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) == .sharingDenied
    }

    /// Fires `onChange` whenever dietary energy or water samples change,
    /// including cross-device (a watch log syncing into the phone's
    /// store) — so widgets/complications refresh in seconds instead of
    /// waiting out the 30-minute timeline window. Background delivery
    /// needs the healthkit.background-delivery entitlement; where it's
    /// unavailable the observer still covers the foreground.
    public func startObservingLogChanges(_ onChange: @escaping @Sendable () async -> Void) {
        // Idempotent: a second registration would double every observer
        // fire (and its widget reload) for the process's lifetime.
        guard !isObservingLogChanges else { return }
        isObservingLogChanges = true
        // .immediate background delivery for both types: water from the
        // watch's dedicated button must reach the phone's water widget
        // promptly (and vice versa) — though NOTE watchOS silently caps
        // most types at hourly, so the watch side leans on its poll.
        // The wake is cheap now — one debounced, kind-scoped reload
        // rendered from PlanCache instead of a per-provider query storm.
        for identifier in [HKQuantityTypeIdentifier.dietaryEnergyConsumed, .dietaryWater] {
            let type = HKQuantityType(identifier)
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
                // Complete AFTER the work: HealthKit re-suspends a
                // background-woken app once completion() runs, and a
                // merely-scheduled Task dies with the suspension.
                // (unsafe transfer: the handler is called once and
                // HealthKit's completion is safe to call off-queue.)
                nonisolated(unsafe) let done = completion
                Task {
                    await onChange()
                    done()
                }
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, error in
                // A missing entitlement is a silent no-op otherwise
                // (CODE_SIGNING_ALLOWED=NO strips it, see CLAUDE.md).
                if let error {
                    print("Onigiri: background delivery unavailable: \(error)")
                }
            }
        }
    }

    /// Fires `onChange` whenever today's ACTIVE energy moves — the one
    /// input that moves the day's budget between midnight and bedtime
    /// (`DayBudget.dayBurn` is `active + max(resting, estimate)`, and the
    /// resting term is flat until measured resting overtakes the
    /// full-day estimate). Without this, nothing anywhere told a widget
    /// that a walk had happened: every reload trigger in the app was a
    /// food/water/library/settings trigger, so the home-screen widget
    /// held its morning number all day while the app — which re-queries
    /// on every foreground — showed the truth (the user, 2026-08-03).
    ///
    /// **Active energy only, deliberately.** Two types were considered
    /// and rejected:
    ///
    /// - `basalEnergyBurned` — flat as a budget input for most of the
    ///   day (see above), and its samples arrive from the same watch
    ///   sync that carries active energy, so the active observer already
    ///   fires in those windows. Pure duplicate wakes.
    /// - `HKWorkoutType` — the tempting one, since a finished workout is
    ///   the single largest jump the budget takes. It is NOT in
    ///   `readTypes`, and adding it would flip
    ///   `statusForAuthorizationRequest` back to `.shouldRequest` until
    ///   the user is re-prompted — which is exactly what
    ///   `PlanCache.needsSetup` reads, so every widget and complication
    ///   would paint "Open Onigiri to set up" over a working setup until
    ///   the app was next opened. A workout writes a batch of active
    ///   energy anyway, and the gate passes on that delta, so the signal
    ///   arrives without the regression.
    ///
    /// The handler is expected to run the burn gate (see
    /// `BurnWidgetRefresh`) — this fires far too often to reload on
    /// directly.
    public func startObservingBurnChanges(_ onChange: @escaping @Sendable () async -> Void) {
        // Idempotent, like the other two: a second registration doubles
        // every fire for the process's lifetime.
        guard !isObservingBurnChanges else { return }
        isObservingBurnChanges = true
        let type = HKQuantityType(.activeEnergyBurned)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
            // Complete AFTER the work, as the log observer does:
            // HealthKit re-suspends a background-woken app once
            // completion() runs, and a merely-scheduled Task dies with
            // the suspension. Three missed completions and HealthKit
            // disables background delivery outright, so this must be
            // reached on every path.
            nonisolated(unsafe) let done = completion
            Task {
                await onChange()
                done()
            }
        }
        store.execute(query)
        // NOTE watchOS silently caps most types at hourly whatever we ask
        // for — the watch therefore does NOT lean on this alone; its
        // scheduled background refresh (WatchBackgroundRefresh) carries
        // the cadence there. On iOS `.immediate` is honored, which is
        // what makes the phone's sub-hour freshness possible.
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, error in
            if let error {
                print("Onigiri: burn background delivery unavailable: \(error)")
            }
        }
    }

    /// Today's active energy alone, in kcal — one statistics query.
    ///
    /// The burn gate runs on every observer fire, which is often; it must
    /// not drag the whole plan pipeline (summary + weight + body profile)
    /// behind it just to answer "did this move enough to matter?".
    public func todayActiveBurnKcal(now: Date = .now) async throws -> Double {
        let (start, end) = Self.dayRange(for: now, now: now)
        return try await sum(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
    }

    /// Weigh-ins recorded ELSEWHERE — the Health app, a smart scale, any
    /// other tracker. The Goal tab's whole chart is built from body-mass
    /// samples this app never writes, and without this it only reloaded
    /// on a tab visit older than its staleness window: a weigh-in taken
    /// while the tab was open never appeared (2026-07-30).
    ///
    /// Deliberately NARROWER than startObservingLogChanges in two ways:
    ///
    /// - **Body mass only, not burn.** The Goal tab also reads active and
    ///   basal energy, but those move continuously while you walk around;
    ///   observing them would fire this constantly for numbers whose whole
    ///   point is a 90-day average. A weigh-in is a discrete event, a few
    ///   times a week at most.
    /// - **No background delivery.** This exists to refresh a VISIBLE
    ///   screen. An observer query already delivers while the app runs;
    ///   background delivery would additionally WAKE the app for a weight
    ///   change nothing else needs — no widget depends on it (the trend
    ///   chart polls on its own) and no reminder reads it.
    public func startObservingWeightChanges(_ onChange: @escaping @Sendable () async -> Void) {
        // Idempotent, for the same reason as the log observer: a second
        // registration doubles every fire for the process's lifetime.
        guard !isObservingWeightChanges else { return }
        isObservingWeightChanges = true
        let type = HKQuantityType(.bodyMass)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
            nonisolated(unsafe) let done = completion
            Task {
                await onChange()
                done()
            }
        }
        store.execute(query)
    }

    #if DEBUG
    private static let debugSeedShareTypes: Set<HKSampleType> = [
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.bodyMass),
        HKQuantityType(.height),
    ]

    /// The seeder's stand-in age, in years.
    ///
    /// Why this exists: the resting ESTIMATE is what credits resting up
    /// front, and `BasalEstimate` needs weight, height, and an age.
    /// Weight and height are samples the seeder writes. Date of birth
    /// is a HealthKit CHARACTERISTIC — no app can write one, only the
    /// person can, in the Health app — so a fresh simulator has none,
    /// the estimate refuses, and the whole earned-budget model silently
    /// degrades to measured-only. That, not "the seeder writes no burn
    /// samples" (it always has), is why none of it rendered on a
    /// simulator. DEBUG-only, read only when Health itself has no
    /// birthday, so it can never mask a real one.
    static let debugSeededAgeKey = "debug.seededAgeYears"

    /// Debug builds that seed sample data need write access to burn/weight
    /// types the real app never writes. Requesting everything in one shot
    /// keeps it to a single permission sheet.
    public func requestDebugSeedAuthorization() async throws {
        try await store.requestAuthorization(
            toShare: Self.shareTypes.union(Self.debugSeedShareTypes),
            read: Self.readTypes
        )
    }
    #endif

    // MARK: - Reads

    public func todaySummary(now: Date = .now) async throws -> DailyEnergySummary {
        try await daySummary(for: now, now: now)
    }

    /// Totals for any calendar day — today ends at `now`, past days at midnight.
    /// Intake and sodium are summed from the day's FOOD CORRELATIONS —
    /// the very rows the day's list renders — not from a statistics
    /// query. Water likewise sums its own samples.
    ///
    /// Why (2026-08-04, the user): a 681 kcal day read as 295. The log
    /// listed all three entries; the totals above them dropped exactly
    /// the sandwich logged on the WATCH. Apple Health showed 295 too.
    ///
    /// MEASURED on device rather than reasoned about — `diagnoseIntake`
    /// exists to re-run it:
    ///
    ///     intake merged=295 bySource=295 corr=681 rows=3
    ///            | com.ecliptik.Onigiri=295 |
    ///
    /// `merged` and `bySource` agree, and `.separateBySource` reports a
    /// SINGLE source — the watch app's bundle never appears. So this is
    /// NOT the cross-source merge discarding a sample (the first theory,
    /// and it was wrong): the watch-logged sample is not visible to a
    /// statistics query on the phone at all, while the correlation that
    /// contains it reads back fine. The underlying HealthKit reason is
    /// still unknown; the behavior is not, and a total summed from
    /// correlations is immune to it either way.
    ///
    /// Burn stays on statistics — there a cross-source merge is exactly
    /// right, because phone and watch really are measuring one body.
    ///
    /// The trade this makes deliberately: food logged into Health by
    /// something OTHER than this app (a manual Health entry, another
    /// tracker) no longer counts toward intake. It never appeared in the
    /// day's list either — `monthStats` already made this same call for
    /// the same reason — so the screen is now self-consistent by
    /// construction rather than by hoping two query kinds agree.
    public func daySummary(for date: Date, now: Date = .now) async throws -> DailyEnergySummary {
        let (start, end) = Self.dayRange(for: date, now: now)
        async let foodsRead = foodCorrelations(start: start, end: end)
        async let active = sum(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let resting = sum(.basalEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let water = waterTotal(start: start, end: end)
        let foods = try await foodsRead
        return try await DailyEnergySummary(
            intakeKcal: foods.reduce(0) { $0 + $1.total(.dietaryEnergyConsumed, unit: .kilocalorie()) },
            activeBurnKcal: active,
            restingBurnKcal: resting,
            sodiumMg: foods.reduce(0) { $0 + $1.total(.dietarySodium, unit: .gramUnit(with: .milli)) },
            waterOz: water
        )
    }

    #if DEBUG
    /// Evidence for the claim in `daySummary`'s note — run it, don't
    /// argue about it (2026-08-04).
    ///
    /// Three readings of one day's intake:
    ///   * merged   — what a plain statistics query returns (what Health
    ///                shows, and what we used to display)
    ///   * bySource — the same query with `.separateBySource`, summed by
    ///                hand across every contributing source
    ///   * corr     — the correlation sum we ship now
    ///
    /// If `merged < bySource` the cross-source merge is discarding
    /// samples, and the per-source breakdown names which source loses.
    /// If they agree, the merge theory is wrong and the real cause is
    /// still open. Timings come along so the correlation path's cost is
    /// measured rather than assumed.
    public func diagnoseIntake(for date: Date = .now, now: Date = .now) async -> String {
        let (start, end) = Self.dayRange(for: date, now: now)
        let type = HKQuantityType(.dietaryEnergyConsumed)
        let inRange = HKQuery.predicateForSamples(
            withStart: start, end: end, options: Self.dayPredicateOptions(for: .dietaryEnergyConsumed)
        )

        let t0 = Date()
        let merged = (try? await sum(.dietaryEnergyConsumed, unit: .kilocalorie(), start: start, end: end)) ?? -1
        let tMerged = Date()

        var perSource: [String: Double] = [:]
        var bySourceTotal = 0.0
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: inRange),
            options: [.cumulativeSum, .separateBySource]
        )
        if let statistics = try? await descriptor.result(for: store) {
            for source in statistics.sources ?? [] {
                let value = statistics.sumQuantity(for: source)?.doubleValue(for: .kilocalorie()) ?? 0
                perSource[source.bundleIdentifier] = value
                bySourceTotal += value
            }
        }
        let tBySource = Date()

        let correlations = (try? await foodCorrelations(start: start, end: end)) ?? []
        let corr = correlations.reduce(0) { $0 + $1.total(.dietaryEnergyConsumed, unit: .kilocalorie()) }
        let tCorr = Date()

        let sources = perSource
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(Int($0.value))" }
            .joined(separator: " ")
        return String(
            format: "intake merged=%.0f bySource=%.0f corr=%.0f rows=%d | %@ | "
                + "ms merged=%.0f bySource=%.0f corr=%.0f",
            merged, bySourceTotal, corr, correlations.count, sources,
            tMerged.timeIntervalSince(t0) * 1000,
            tBySource.timeIntervalSince(tMerged) * 1000,
            tCorr.timeIntervalSince(tBySource) * 1000
        )
    }
    #endif

    /// The day's food correlations — the ONE source every food total is
    /// summed from, shared by the list and the summary so they cannot
    /// disagree. Deliberately does NOT touch `correlationCache`: that
    /// cache backs deletion by id and belongs to `foodEntries`, which
    /// knows it is loading the rows the user can act on.
    private func foodCorrelations(start: Date, end: Date) async throws -> [HKCorrelation] {
        let inRange = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.food), predicate: inRange)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        do {
            return try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined {
            return []
        }
    }

    /// Water summed from its own samples, for the same reason food is
    /// summed from correlations: water is logged as bare samples on BOTH
    /// devices, so a statistics query can merge a watch serving away
    /// against a phone one logged in the same window.
    private func waterTotal(start: Date, end: Date) async throws -> Double {
        let inRange = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.dietaryWater), predicate: inRange)],
            sortDescriptors: []
        )
        do {
            return try await descriptor.result(for: store)
                .reduce(0) { $0 + $1.quantity.doubleValue(for: .fluidOunceUS()) }
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined {
            return 0
        }
    }

    private static func dayRange(for date: Date, now: Date) -> (start: Date, end: Date) {
        DayBounds.range(for: date, now: now)
    }

    /// A day's all-sources total for one tracked nutrient, in its label
    /// unit — Today's configurable metric slots read this.
    public func dayTotal(of nutrient: TrackedNutrient, for date: Date = .now, now: Date = .now) async throws -> Double {
        let (start, end) = Self.dayRange(for: date, now: now)
        // Correlation-summed like every other food total (see
        // daySummary) — a tracked slot showing a merged number beside a
        // list that disagrees is the same bug wearing a different hat.
        // Water is the exception on the way in, not the way out: it is
        // logged as bare samples, so it sums samples instead.
        guard nutrient != .water else { return try await waterTotal(start: start, end: end) }
        return try await foodCorrelations(start: start, end: end).reduce(0) {
            $0 + $1.total(nutrient.healthKitIdentifier, unit: nutrient.healthKitUnit)
        }
    }

    /// Burn samples can span midnight (a watch basal row can run
    /// 22:00→02:00); the default overlap predicate lets the statistics
    /// engine apportion them across days. .strictStartDate DROPPED the
    /// post-midnight slice from both days — a small systematic burn
    /// undercount every night. Instantaneous dietary/water samples
    /// keep strict, which correctly stops a boundary sample from
    /// matching two days.
    private static func dayPredicateOptions(for identifier: HKQuantityTypeIdentifier) -> HKQueryOptions {
        identifier == .activeEnergyBurned || identifier == .basalEnergyBurned
            ? [] : .strictStartDate
    }

    private func sum(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date
    ) async throws -> Double {
        let inToday = HKQuery.predicateForSamples(
            withStart: start, end: end,
            options: Self.dayPredicateOptions(for: identifier)
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: inToday),
            options: .cumulativeSum
        )
        do {
            let statistics = try await descriptor.result(for: store)
            return statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
        } catch let error as HKError where error.code == .errorNoData || error.code == .errorAuthorizationNotDetermined {
            // Undetermined reads behave like denied reads elsewhere in
            // HealthKit (silently empty); prompting is start()'s job.
            return 0
        }
    }

    /// True when reads fail because the device is locked (file
    /// protection seals the Health store until first unlock). A
    /// background widget reload hitting a sealed store reads empty and
    /// replaced a correct widget with confident zeros until the next
    /// unlock — callers keep their last-good snapshot instead.
    public func isStoreLocked() async -> Bool {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.dietaryEnergyConsumed))],
            sortDescriptors: [], limit: 1
        )
        do {
            _ = try await descriptor.result(for: store)
            return false
        } catch let error as HKError where error.code == .errorDatabaseInaccessible {
            return true
        } catch {
            return false
        }
    }

    /// Most recent weight sample (smart scale writes these), in pounds.
    /// Write-through cached in the App Group (day-stamped) so the watch
    /// context push — a synchronous path — can read it without a query.
    public func latestBodyMassLb() async throws -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        let result: Double?
        do {
            result = try await descriptor.result(for: store).first?.quantity.doubleValue(for: .pound())
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined {
            return nil
        }
        if let result {
            SharedStore.defaults.set(
                ["value": result, "day": DeficitTargetHistory.dayKey(for: .now)] as [String: Any],
                forKey: Self.weightCacheKey
            )
        } else {
            // All weigh-ins deleted: a lingering cache would push a
            // phantom weight to the watch until the day window aged out.
            SharedStore.defaults.removeObject(forKey: Self.weightCacheKey)
        }
        return result
    }

    private static let weightCacheKey = "latestBodyMassLb"

    static func burnCacheKey(days: Int) -> String { "averageDailyBurnKcal.\(days)" }

    /// The last weight read's write-through, same shape as the burn cache.
    public static func cachedLatestBodyMassLb() -> (lb: Double, day: String)? {
        guard let cached = SharedStore.defaults.dictionary(forKey: weightCacheKey),
              let value = cached["value"] as? Double,
              let day = cached["day"] as? String else { return nil }
        return (value, day)
    }

    /// Mean of (active + resting) burn over the last `days` full days,
    /// skipping days with implausibly little data. Nil if there's no history.
    ///
    /// Today is excluded (it's partial), so the result barely moves within
    /// a day — yet it used to be recomputed (two 14-day collection
    /// queries) inside every plan load, on every widget refresh and
    /// foreground. Cached in the App Group so every process shares one
    /// computation. The 15-minute TTL (not the whole day) lets a watch
    /// syncing yesterday's burn late self-correct like the uncached code
    /// did; a nil result (no history yet) is never cached — granting
    /// Health access mid-day must take effect.
    public func averageDailyBurnKcal(days: Int = 14, now: Date = .now) async throws -> Double? {
        let calendar = Calendar.current
        let cacheKey = Self.burnCacheKey(days: days)
        let dayKey = DeficitTargetHistory.dayKey(for: now, calendar: calendar)
        if let cached = SharedStore.defaults.dictionary(forKey: cacheKey),
           cached["day"] as? String == dayKey,
           let value = cached["value"] as? Double,
           let stamp = cached["stamp"] as? Double,
           now.timeIntervalSince1970 - stamp < 15 * 60 {
            return value
        }
        let end = calendar.startOfDay(for: now) // exclude today; it's partial
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return nil }
        async let active = dailyTotals(.activeEnergyBurned, start: start, end: end)
        async let basal = dailyTotals(.basalEnergyBurned, start: start, end: end)
        var totals = try await active
        for (day, kcal) in try await basal {
            totals[day, default: 0] += kcal
        }
        let fullDays = totals.values.filter { $0 > 800 }
        guard !fullDays.isEmpty else { return nil }
        let average = fullDays.reduce(0, +) / Double(fullDays.count)
        SharedStore.defaults.set(
            ["day": dayKey, "value": average, "stamp": now.timeIntervalSince1970] as [String: Any],
            forKey: cacheKey
        )
        return average
    }

    /// Per-day intake, summed from food correlations and bucketed by the
    /// calendar day each one starts in — the day-keyed twin of
    /// `daySummary`'s intake, so the calendar and Today can't disagree.
    /// One query for the whole range; food correlations are instantaneous,
    /// so no apportioning across midnight is needed (unlike burn).
    private func dailyIntakeTotals(start: Date, end: Date) async throws -> [Date: Double] {
        let calendar = Calendar.current
        var totals: [Date: Double] = [:]
        for correlation in try await foodCorrelations(start: start, end: end) {
            let day = calendar.startOfDay(for: correlation.startDate)
            let kcal = correlation.total(.dietaryEnergyConsumed, unit: .kilocalorie())
            guard kcal > 0 else { continue }
            totals[day, default: 0] += kcal
        }
        return totals
    }

    private func dailyTotals(
        _ identifier: HKQuantityTypeIdentifier, start: Date, end: Date
    ) async throws -> [Date: Double] {
        let inRange = HKQuery.predicateForSamples(
            withStart: start, end: end,
            options: Self.dayPredicateOptions(for: identifier)
        )
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: inRange),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection: HKStatisticsCollection
        do {
            collection = try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined {
            return [:]
        }
        var totals: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            if let sum = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()), sum > 0 {
                totals[statistics.startDate] = sum
            }
        }
        return totals
    }

    /// Height, age, and sex — the inputs a resting-burn estimate needs
    /// beyond weight. Any of them missing returns nil for that piece;
    /// height comes from the most recent sample, since it's the only one
    /// of the three that's a measurement rather than a characteristic.
    ///
    /// Characteristic reads throw when unauthorized rather than returning
    /// empty, so each is caught separately: a missing date of birth must
    /// not also cost us the height.
    public func bodyProfile() async -> (heightCm: Double?, ageYears: Int?, sex: BasalEstimate.Sex) {
        let height = try? await latestQuantity(
            .height, unit: .meterUnit(with: .centi))
        var age: Int?
        if let components = try? store.dateOfBirthComponents(),
           let birthday = Calendar.current.date(from: components) {
            age = Calendar.current.dateComponents([.year], from: birthday, to: .now).year
        }
        #if DEBUG
        // Simulator seeding only, and only as a fallback — a real
        // birthday always wins. See debugSeededAgeKey for why an app
        // can't just write one.
        if age == nil {
            let seeded = SharedStore.defaults.integer(forKey: Self.debugSeededAgeKey)
            if seeded > 0 { age = seeded }
        }
        #endif
        let sex: BasalEstimate.Sex = switch try? store.biologicalSex().biologicalSex {
        case .male: .male
        case .female: .female
        default: .unspecified
        }
        return (height, age, sex)
    }

    /// The most recent sample of a quantity type, in the given unit.
    private func latestQuantity(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit
    ) async throws -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: store)
            .first?.quantity.doubleValue(for: unit)
    }

    /// Weigh-ins over the trailing `days`, date-ascending, in pounds.
    public func bodyMassHistory(days: Int = 90, now: Date = .now) async throws -> [WeightTrend.Point] {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return [] }
        return try await bodyMassHistory(from: start, to: now)
    }

    /// Weigh-ins for an arbitrary range — the calendar extends its year
    /// of history on demand when older months are browsed.
    public func bodyMassHistory(from start: Date, to end: Date) async throws -> [WeightTrend.Point] {
        let inRange = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: inRange)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            return try await descriptor.result(for: store).map {
                WeightTrend.Point(date: $0.startDate, weightLb: $0.quantity.doubleValue(for: .pound()))
            }
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined {
            return []
        }
    }

    /// Per-day intake and burn totals over the trailing `days` (plus today),
    /// for the streak calendar. Days with no data at all are omitted.
    public func dailyEnergyTotals(days: Int = 92, now: Date = .now) async throws -> [DayEnergyTotals] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else {
            return []
        }
        return try await dailyEnergyTotals(from: start, to: now)
    }

    /// Per-day totals for an arbitrary range — the calendar loads months
    /// browsed beyond the trailing window on demand.
    ///
    /// This is THE day-burn figure: badges, streaks, the calendar's day
    /// card, and (for completed days) the Today screen all read it, so
    /// they can't disagree about whether a day earned its badge.
    ///
    /// Each day's burn is `DayBudget.dayBurn` — resting credited up
    /// front (measured, floored by the body-metric estimate), plus
    /// whatever active energy was actually earned.
    public func dailyEnergyTotals(from start: Date, to end: Date) async throws -> [DayEnergyTotals] {
        // Intake per day comes from the correlations, NOT the statistics
        // collection: the collection merges across sources exactly as
        // `sum` does, so a day with logs from both devices was judged on
        // an undercount — and at 295 against a real 681 it fell under
        // `untrackedBelowKcal`, so the calendar would have called a
        // fully-logged day untracked (2026-08-04). Burn keeps the
        // collection; see the day-bucketing note on alignedDaySummary.
        async let intakeTotals = dailyIntakeTotals(start: start, end: end)
        async let activeTotals = dailyTotals(.activeEnergyBurned, start: start, end: end)
        async let basalTotals = dailyTotals(.basalEnergyBurned, start: start, end: end)
        let (intake, active, basal) = try await (intakeTotals, activeTotals, basalTotals)
        let latestWeightLb = try? await latestBodyMassLb()
        // Resting up front, active earned (the user's rule, 2026-08-02).
        // The estimate floors RESTING only, so an unworn day still gets
        // its baseline but earns no activity — which is the point: the
        // watch is how active energy is earned. One profile read covers
        // every day in the range; body metrics don't move day to day at
        // a resolution this equation can see.
        let profile = await bodyProfile()
        let estimatedResting: Double? = {
            guard let heightCm = profile.heightCm, let age = profile.ageYears,
                  let weightLb = latestWeightLb
            else { return nil }
            return BasalEstimate.restingKcal(
                weightLb: weightLb, heightCm: heightCm,
                ageYears: age, sex: profile.sex)
        }()
        let allDays = Set(intake.keys).union(active.keys).union(basal.keys)
        return allDays.sorted().map { day in
            return DayEnergyTotals(
                day: day,
                intakeKcal: intake[day] ?? 0,
                burnKcal: DayBudget.dayBurn(
                    activeKcal: active[day] ?? 0,
                    restingKcal: basal[day] ?? 0,
                    estimatedRestingKcal: estimatedResting)
            )
        }
    }

    /// A day's summary sourced so it can't disagree with the calendar:
    /// burn comes from the SAME day-bucketed collection every badge,
    /// streak, and calendar verdict reads.
    ///
    /// `daySummary`'s plain `sum` matches whole samples that OVERLAP the
    /// day, so a basal row running 23:30→00:30 lands in full on BOTH
    /// adjacent days; the collection query apportions it across the
    /// boundary instead. That was the Today-vs-calendar burn gap (2,809
    /// against 2,759 for one day, 2026-07-30). Intake, sodium and water
    /// stay on `daySummary` — which since 2026-08-04 sums the day's own
    /// correlations and water samples rather than a merged statistics
    /// query, so those agree with the calendar (and with the list) by
    /// construction rather than by coincidence.
    public func alignedDaySummary(for date: Date, now: Date = .now) async throws -> DailyEnergySummary {
        let summary = try await daySummary(for: date, now: now)
        let (start, end) = Self.dayRange(for: date, now: now)
        async let activeRead = dailyTotals(.activeEnergyBurned, start: start, end: end)
        async let basalRead = dailyTotals(.basalEnergyBurned, start: start, end: end)
        let dayStart = Calendar.current.startOfDay(for: date)
        // A missing bucket is a genuine zero; only a FAILED read falls
        // back to the sum, so the paths can't quietly diverge again.
        let active = (try? await activeRead).map { $0[dayStart] ?? 0 } ?? summary.activeBurnKcal
        let resting = (try? await basalRead).map { $0[dayStart] ?? 0 } ?? summary.restingBurnKcal
        return DailyEnergySummary(
            intakeKcal: summary.intakeKcal,
            activeBurnKcal: active,
            restingBurnKcal: resting,
            sodiumMg: summary.sodiumMg,
            waterOz: summary.waterOz
        )
    }


    // MARK: - Water log

    private var waterSampleCache: [UUID: HKQuantitySample] = [:]

    /// Returns the sample UUID so the log can be undone.
    @discardableResult
    public func logWater(oz: Double, date: Date = .now) async throws -> UUID {
        let sample = HKQuantitySample(
            type: HKQuantityType(.dietaryWater),
            quantity: HKQuantity(unit: .fluidOunceUS(), doubleValue: oz),
            start: date, end: date,
            // Manually entered, not sensor-derived — Health uses this
            // for source distinction and Journal suggestions.
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        try await store.save(sample)
        waterSampleCache[sample.uuid] = sample
        return sample.uuid
    }

    /// Today's water servings from all sources, newest first.
    public func todayWaterEntries(now: Date = .now) async throws -> [WaterLogEntry] {
        try await waterEntries(on: now, now: now)
    }

    /// Water servings for any calendar day, newest first.
    public func waterEntries(on date: Date, now: Date = .now) async throws -> [WaterLogEntry] {
        let (start, end) = Self.dayRange(for: date, now: now)
        let inToday = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.dietaryWater), predicate: inToday)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let samples: [HKQuantitySample]
        do {
            samples = try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined {
            return []
        }
        waterSampleCache = Dictionary(uniqueKeysWithValues: samples.map { ($0.uuid, $0) })
        // (editable mirrors the food entries: reads span all sources,
        // deletes only reach this app family's own samples.)
        return samples.map {
            WaterLogEntry(
                id: $0.uuid, oz: $0.quantity.doubleValue(for: .fluidOunceUS()),
                date: $0.startDate,
                editable: Self.isFamilySource($0.sourceRevision.source)
            )
        }
    }

    public func deleteWaterEntry(id: UUID) async throws {
        if let sample = waterSampleCache.removeValue(forKey: id) {
            try await store.delete(sample)
            return
        }
        // Cache miss (fresh service instance, or the list was reloaded):
        // fetch the sample by UUID so the delete still lands.
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: HKQuantityType(.dietaryWater),
                predicate: HKQuery.predicateForObject(with: id)
            )],
            sortDescriptors: []
        )
        guard let sample = try await descriptor.result(for: store).first else { return }
        try await store.delete(sample)
    }

    // MARK: - Food log (writes)

    /// Log an eating event as an HKCorrelation(.food) wrapping energy,
    /// sodium, and any known extended nutrients, named via metadata so the
    /// log can be listed later. Returns the correlation UUID for undo.
    /// Custom metadata key carrying the meal slot (FoodCategory rawValue).
    public static let mealCategoryMetadataKey = "OnigiriMealCategory"
    /// Custom metadata key marking an entry whose values came from an
    /// AI estimate — read back for the ✨ mark on log rows.
    public static let aiGeneratedMetadataKey = "OnigiriAIGenerated"
    /// Custom metadata key carrying how many portions the totals
    /// represent — the edit sheet reads it back so a 3-portion log
    /// edits as 3, not as one triple-sized serving. Absent means 1
    /// (older logs, other apps).
    public static let quantityMetadataKey = "OnigiriQuantity"
    /// Custom metadata key carrying a logged MEAL's composition —
    /// JSON-encoded [LoggedMealItem] on the per-portion basis. Absent
    /// means a plain food, or a meal logged before the key existed.
    /// Like quantity, every log/re-log path must carry it through or
    /// history silently loses its breakdown.
    public static let mealItemsMetadataKey = "OnigiriMealItems"

    @discardableResult
    public func logFood(
        name: String,
        kcal: Double,
        sodiumMg: Double,
        nutrients: NutrientValues = NutrientValues(),
        category: FoodCategory? = nil,
        date: Date = .now,
        aiGenerated: Bool = false,
        quantity: Double = 1,
        mealItems: [LoggedMealItem] = []
    ) async throws -> UUID {
        var metadata: [String: Any] = [
            HKMetadataKeyFoodType: name,
            // Manually entered, not sensor-derived — Health uses this
            // for source distinction and Journal suggestions.
            HKMetadataKeyWasUserEntered: true,
        ]
        if let category {
            metadata[Self.mealCategoryMetadataKey] = category.rawValue
        }
        if aiGenerated {
            metadata[Self.aiGeneratedMetadataKey] = true
        }
        if quantity != 1, quantity > 0, quantity.isFinite {
            metadata[Self.quantityMetadataKey] = quantity
        }
        if let encoded = LoggedMealItem.encoded(mealItems) {
            metadata[Self.mealItemsMetadataKey] = encoded
        }
        var objects: Set<HKSample> = [
            HKQuantitySample(
                type: HKQuantityType(.dietaryEnergyConsumed),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                start: date, end: date
            )
        ]
        func insert(_ identifier: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double?) {
            let type = HKQuantityType(identifier)
            // Positive value AND write-authorized — the tested policy
            // (one unauthorized sample fails the whole correlation;
            // skipped nutrients still ride the food library's copy).
            guard let value, CorrelationWritePolicy.includes(
                value: value,
                isWriteAuthorized: store.authorizationStatus(for: type) == .sharingAuthorized
            ) else { return }
            objects.insert(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: date, end: date
            ))
        }
        insert(.dietarySodium, .gramUnit(with: .milli), sodiumMg)
        insert(.dietaryFatTotal, .gram(), nutrients.fatG)
        // Trans fat has no HealthKit type; it stays app-only.
        insert(.dietaryFatSaturated, .gram(), nutrients.saturatedFatG)
        insert(.dietaryFatPolyunsaturated, .gram(), nutrients.polyunsaturatedFatG)
        insert(.dietaryFatMonounsaturated, .gram(), nutrients.monounsaturatedFatG)
        insert(.dietaryCholesterol, .gramUnit(with: .milli), nutrients.cholesterolMg)
        insert(.dietaryCarbohydrates, .gram(), nutrients.carbsG)
        insert(.dietaryProtein, .gram(), nutrients.proteinG)
        insert(.dietaryFiber, .gram(), nutrients.fiberG)
        insert(.dietarySugar, .gram(), nutrients.sugarG)
        insert(.dietaryCaffeine, .gramUnit(with: .milli), nutrients.caffeineMg)
        for micro in Micronutrient.allCases {
            insert(micro.healthKitIdentifier, micro.healthKitUnit, nutrients[micro])
        }
        let correlation = HKCorrelation(
            type: HKCorrelationType(.food),
            start: date, end: date,
            objects: objects,
            metadata: metadata
        )
        try await store.save(correlation)
        // Cache so deleteFoodEntry(id:) can undo without a re-query.
        correlationCache[correlation.uuid] = correlation
        return correlation.uuid
    }

    /// Today's logged eating events, newest first. Caches the underlying
    /// correlations so entries can be deleted by id.
    private var correlationCache: [UUID: HKCorrelation] = [:]

    public func todayFoodEntries(now: Date = .now) async throws -> [FoodLogEntry] {
        try await foodEntries(on: now, now: now)
    }

    /// Month aggregates for the Month Details screen: total water and
    /// how many eating events were logged.
    public func monthStats(for month: Date, now: Date = .now) async throws -> (waterOz: Double, foodEntryCount: Int) {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) else {
            return (0, 0)
        }
        let end = min(nextMonth, now)
        // Sample-summed, like every other water total (see waterTotal):
        // a merged month would drop watch servings against phone ones.
        async let water = waterTotal(start: start, end: end)
        // Correlations, not bare energy samples: the day lists render
        // food correlations, and the month count must agree with them
        // (bare samples from the Health app or other trackers don't
        // appear in the day lists).
        let inMonth = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.food), predicate: inMonth)],
            sortDescriptors: []
        )
        let count: Int
        do {
            count = try await descriptor.result(for: store).count
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined {
            count = 0
        }
        return try await (water, count)
    }

    /// Logged eating events for any calendar day, newest first.
    public func foodEntries(on date: Date, now: Date = .now) async throws -> [FoodLogEntry] {
        let (start, end) = Self.dayRange(for: date, now: now)
        // Same fetch the day's totals sum (see daySummary) — one source
        // for the rows and the number above them.
        let correlations = try await foodCorrelations(start: start, end: end)
        correlationCache = Dictionary(uniqueKeysWithValues: correlations.map { ($0.uuid, $0) })
        return correlations.map(Self.entry(from:))
    }

    /// Distinct foods logged over the trailing week, newest first — the
    /// Log sheet's Recent section. Leaves the deletion cache alone: these
    /// entries are re-logged, never deleted from here.
    public func recentFoodEntries(days: Int = 7, limit: Int = 10, now: Date = .now) async throws -> [FoodLogEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now)
        let inWindow = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.food), predicate: inWindow)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        do {
            return try await descriptor.result(for: store)
                .map(Self.entry(from:))
                .uniquedByName(limit: limit)
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined {
            return []
        }
    }

    private static func entry(from correlation: HKCorrelation) -> FoodLogEntry {
        FoodLogEntry(
            id: correlation.uuid,
            name: correlation.metadata?[HKMetadataKeyFoodType] as? String ?? "Food",
            kcal: correlation.total(.dietaryEnergyConsumed, unit: .kilocalorie()),
            sodiumMg: correlation.total(.dietarySodium, unit: .gramUnit(with: .milli)),
            date: correlation.startDate,
            category: (correlation.metadata?[Self.mealCategoryMetadataKey] as? String)
                .flatMap(FoodCategory.init(rawValue:)),
            nutrients: correlation.nutrientValues,
            editable: Self.isFamilySource(correlation.sourceRevision.source),
            aiGenerated: correlation.metadata?[Self.aiGeneratedMetadataKey] as? Bool ?? false,
            quantity: correlation.metadata?[Self.quantityMetadataKey] as? Double ?? 1,
            mealItems: LoggedMealItem.decoded(
                from: correlation.metadata?[Self.mealItemsMetadataKey] as? String)
        )
    }

    /// Whether a sample came from this app or its watch/phone counterpart
    /// (bundle ids differ only by a suffix, e.g. `.watchkitapp`). Reads
    /// include every source by design; delete/edit affordances should
    /// not be offered on rows HealthKit will refuse to delete — only an
    /// object's own saver (or close family) may remove it.
    private static func isFamilySource(_ source: HKSource) -> Bool {
        let mine = HKSource.default().bundleIdentifier
        let theirs = source.bundleIdentifier
        return theirs == mine
            || theirs.hasPrefix(mine + ".")
            || mine.hasPrefix(theirs + ".")
    }

    /// True when a failed delete/edit means "saved by another app" —
    /// the caller should say so instead of blaming Health access.
    public static func isForeignObjectError(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorAuthorizationDenied
    }

    /// Delete a logged entry (and its contained samples) by correlation UUID.
    /// Falls back to a UUID query when the correlation isn't cached (fresh
    /// service instance, or the cache was replaced by browsing another day) —
    /// undo must never silently no-op.
    public func deleteFoodEntry(id: UUID) async throws {
        let correlation: HKCorrelation
        if let cached = correlationCache.removeValue(forKey: id) {
            correlation = cached
        } else {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.correlation(
                    type: HKCorrelationType(.food),
                    predicate: HKQuery.predicateForObject(with: id)
                )],
                sortDescriptors: []
            )
            guard let fetched = try await descriptor.result(for: store).first else { return }
            correlation = fetched
        }
        try await store.delete(Array(correlation.objects) + [correlation])
    }

    // MARK: - Debug seeding

    #if DEBUG
    /// Simulator helper: writes plausible intake/burn/water samples so the
    /// meter has data. Call requestDebugSeedAuthorization() first — this
    /// assumes write access to the burn/weight types is already granted.
    public func seedSampleData(now: Date = .now) async throws {
        // All times are anchored inside calendar days so the seed behaves the
        // same at any hour — a span crossing midnight would be apportioned
        // across days by HealthKit statistics and skew per-day totals.
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let elapsedToday = max(now.timeIntervalSince(todayStart), 60)
        func todayAt(_ fraction: Double) -> Date {
            todayStart.addingTimeInterval(elapsedToday * fraction)
        }

        func sample(
            _ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double,
            start: Date, end: Date
        ) -> HKQuantitySample {
            HKQuantitySample(
                type: HKQuantityType(id),
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: start, end: end
            )
        }

        // The body the resting estimate is computed from. Height is the
        // one of the three inputs that is a SAMPLE (weight is seeded
        // below; age can't be written at all — debugSeededAgeKey).
        // 178 cm against the seeded ~200 lb and 40 years gives a
        // resting estimate near 1,740 kcal, comfortably above the 1,120
        // of basal seeded for today — which is the point: it makes the
        // estimate visibly FLOOR a partial day's resting, the behavior
        // the whole model turns on and that no simulator could show.
        SharedStore.defaults.set(40, forKey: Self.debugSeededAgeKey)
        var samples = [
            sample(.height, .meterUnit(with: .centi), 178,
                   start: todayStart, end: todayStart),
            // energy burn accrued so far today
            sample(.activeEnergyBurned, .kilocalorie(), 385, start: todayAt(0.1), end: todayAt(0.6)),
            sample(.basalEnergyBurned, .kilocalorie(), 1120, start: todayAt(0), end: todayAt(0.95)),
            // two glasses of water
            sample(.dietaryWater, .fluidOunceUS(), 12, start: todayAt(0.4), end: todayAt(0.4)),
            sample(.dietaryWater, .fluidOunceUS(), 12, start: todayAt(0.9), end: todayAt(0.9)),
        ]
        // a month of daily weigh-ins drifting 202 → 200 lb with scale noise.
        // The noise stays UNDER the drift on purpose: at ±0.6 it swamped
        // the -0.47 lb/week signal, and the weekly fit (v2.9.0 reads raw
        // weigh-ins) rendered "Scale: up 0.2 lb this week" — a
        // weight-loss demo contradicting itself in every capture.
        let wobble: [Double] = [0.2, -0.15, 0.25, -0.2, 0.05, 0.15, -0.2]
        for day in 0...30 {
            let trend = 202.0 - (Double(day) / 30.0) * 2.0
            guard let dayStart = calendar.date(byAdding: .day, value: day - 30, to: todayStart) else { continue }
            let morning = dayStart.addingTimeInterval(7 * 3600)
            samples.append(sample(
                .bodyMass, .pound(), trend + wobble[day % wobble.count],
                start: morning, end: morning
            ))
        }
        // three full days of history so the 14-day average has data and the
        // streak calendar has earned days (2300 burn − 1550 eaten = 750 deficit)
        for day in 1...3 {
            guard let dayStart = calendar.date(byAdding: .day, value: -day, to: todayStart) else { continue }
            samples.append(sample(
                .activeEnergyBurned, .kilocalorie(), 500,
                start: dayStart.addingTimeInterval(9 * 3600),
                end: dayStart.addingTimeInterval(19 * 3600)
            ))
            samples.append(sample(
                .basalEnergyBurned, .kilocalorie(), 1800,
                start: dayStart.addingTimeInterval(1 * 3600),
                end: dayStart.addingTimeInterval(22 * 3600)
            ))
        }
        try await store.save(samples)

        // breakfast and lunch as named food correlations, with label-style
        // nutrients so the day-detail screen has something to show
        var eggs = NutrientValues(
            fatG: 22, saturatedFatG: 7, polyunsaturatedFatG: 3,
            monounsaturatedFatG: 9, cholesterolMg: 375,
            carbsG: 30, proteinG: 24, fiberG: 2, sugarG: 3
        )
        eggs[.iron] = 3
        eggs[.calcium] = 120
        eggs[.potassium] = 300
        eggs[.vitaminD] = 2
        eggs[.folate] = 80
        var burrito = NutrientValues(
            fatG: 24, saturatedFatG: 9, polyunsaturatedFatG: 3.5,
            monounsaturatedFatG: 8, cholesterolMg: 95,
            carbsG: 72, proteinG: 42, fiberG: 8, sugarG: 4
        )
        burrito[.potassium] = 850
        burrito[.calcium] = 250
        burrito[.iron] = 4.5
        burrito[.magnesium] = 90
        burrito[.zinc] = 4
        burrito[.vitaminC] = 12
        burrito[.vitaminA] = 150
        try await logFood(name: "Two eggs & toast", kcal: 420, sodiumMg: 610,
                          nutrients: eggs, date: todayAt(0.25))
        try await logFood(name: "Chicken burrito", kcal: 680, sodiumMg: 940,
                          nutrients: burrito, date: todayAt(0.75))
        // past days' intake as named logs so day browsing has entries
        for day in 1...3 {
            guard let dayStart = calendar.date(byAdding: .day, value: -day, to: todayStart) else { continue }
            try await logFood(name: "Two eggs & toast", kcal: 650, sodiumMg: 800,
                              date: dayStart.addingTimeInterval(8 * 3600))
            try await logFood(name: "Chicken & rice", kcal: 900, sodiumMg: 1000,
                              date: dayStart.addingTimeInterval(18 * 3600))
        }
    }
    #endif
}

extension TrackedNutrient {
    var healthKitIdentifier: HKQuantityTypeIdentifier {
        switch self {
        case .water: .dietaryWater
        case .sodium: .dietarySodium
        case .fat: .dietaryFatTotal
        case .saturatedFat: .dietaryFatSaturated
        case .polyunsaturatedFat: .dietaryFatPolyunsaturated
        case .monounsaturatedFat: .dietaryFatMonounsaturated
        case .cholesterol: .dietaryCholesterol
        case .carbs: .dietaryCarbohydrates
        case .protein: .dietaryProtein
        case .fiber: .dietaryFiber
        case .sugar: .dietarySugar
        case .caffeine: .dietaryCaffeine
        case .micro(let micro): micro.healthKitIdentifier
        }
    }

    var healthKitUnit: HKUnit {
        switch self {
        case .water: .fluidOunceUS()
        case .sodium, .cholesterol, .caffeine: .gramUnit(with: .milli)
        case .fat, .saturatedFat, .polyunsaturatedFat, .monounsaturatedFat,
             .carbs, .protein, .fiber, .sugar: .gram()
        case .micro(let micro): micro.healthKitUnit
        }
    }
}

extension Micronutrient {
    var healthKitIdentifier: HKQuantityTypeIdentifier {
        switch self {
        case .potassium: .dietaryPotassium
        case .calcium: .dietaryCalcium
        case .iron: .dietaryIron
        case .magnesium: .dietaryMagnesium
        case .zinc: .dietaryZinc
        case .phosphorus: .dietaryPhosphorus
        case .selenium: .dietarySelenium
        case .copper: .dietaryCopper
        case .manganese: .dietaryManganese
        case .iodine: .dietaryIodine
        case .chromium: .dietaryChromium
        case .molybdenum: .dietaryMolybdenum
        case .chloride: .dietaryChloride
        case .vitaminA: .dietaryVitaminA
        case .vitaminC: .dietaryVitaminC
        case .vitaminD: .dietaryVitaminD
        case .vitaminE: .dietaryVitaminE
        case .vitaminB6: .dietaryVitaminB6
        case .vitaminB12: .dietaryVitaminB12
        case .folate: .dietaryFolate
        case .vitaminK: .dietaryVitaminK
        case .thiamin: .dietaryThiamin
        case .riboflavin: .dietaryRiboflavin
        case .niacin: .dietaryNiacin
        case .pantothenicAcid: .dietaryPantothenicAcid
        case .biotin: .dietaryBiotin
        }
    }

    var healthKitUnit: HKUnit {
        switch unit {
        case .milligrams: .gramUnit(with: .milli)
        case .micrograms: .gramUnit(with: .micro)
        }
    }
}

private extension HKCorrelation {
    func total(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) -> Double {
        objects(for: HKQuantityType(identifier))
            .compactMap { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: unit) }
            .reduce(0, +)
    }

    /// Like total, but nil when the correlation carries no sample of the
    /// type — "absent" and "zero" must round-trip differently.
    func totalIfPresent(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) -> Double? {
        objects(for: HKQuantityType(identifier)).isEmpty
            ? nil : total(identifier, unit: unit)
    }

    /// The extended nutrients written by logFood, read back. Trans fat is
    /// the one field that can't round-trip (no HealthKit type).
    var nutrientValues: NutrientValues {
        var values = NutrientValues(
            fatG: totalIfPresent(.dietaryFatTotal, unit: .gram()),
            saturatedFatG: totalIfPresent(.dietaryFatSaturated, unit: .gram()),
            polyunsaturatedFatG: totalIfPresent(.dietaryFatPolyunsaturated, unit: .gram()),
            monounsaturatedFatG: totalIfPresent(.dietaryFatMonounsaturated, unit: .gram()),
            cholesterolMg: totalIfPresent(.dietaryCholesterol, unit: .gramUnit(with: .milli)),
            carbsG: totalIfPresent(.dietaryCarbohydrates, unit: .gram()),
            proteinG: totalIfPresent(.dietaryProtein, unit: .gram()),
            fiberG: totalIfPresent(.dietaryFiber, unit: .gram()),
            sugarG: totalIfPresent(.dietarySugar, unit: .gram()),
            caffeineMg: totalIfPresent(.dietaryCaffeine, unit: .gramUnit(with: .milli))
        )
        for micro in Micronutrient.allCases {
            values[micro] = totalIfPresent(micro.healthKitIdentifier, unit: micro.healthKitUnit)
        }
        return values
    }
}
#endif
