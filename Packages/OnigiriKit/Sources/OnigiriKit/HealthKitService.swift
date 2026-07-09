#if canImport(HealthKit)
import Foundation
import HealthKit

/// All HealthKit access for Onigiri. HealthKit is the log store: food energy,
/// sodium, and water are written as samples; energy burn and weight are read.
/// See docs/PLAN.md.
@MainActor
public final class HealthKitService {
    public static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store = HKHealthStore()

    public init() {}

    // MARK: - Authorization

    private static let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietarySodium),
        HKQuantityType(.dietaryWater),
    ]

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietarySodium),
        HKQuantityType(.dietaryWater),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.bodyMass),
    ]

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

    #if DEBUG
    private static let debugSeedShareTypes: Set<HKSampleType> = [
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.bodyMass),
    ]

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
        async let intake = sumToday(.dietaryEnergyConsumed, unit: .kilocalorie(), now: now)
        async let active = sumToday(.activeEnergyBurned, unit: .kilocalorie(), now: now)
        async let resting = sumToday(.basalEnergyBurned, unit: .kilocalorie(), now: now)
        async let sodium = sumToday(.dietarySodium, unit: .gramUnit(with: .milli), now: now)
        async let water = sumToday(.dietaryWater, unit: .fluidOunceUS(), now: now)
        return try await DailyEnergySummary(
            intakeKcal: intake,
            activeBurnKcal: active,
            restingBurnKcal: resting,
            sodiumMg: sodium,
            waterOz: water
        )
    }

    private func sumToday(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit, now: Date
    ) async throws -> Double {
        let startOfDay = Calendar.current.startOfDay(for: now)
        let inToday = HKQuery.predicateForSamples(
            withStart: startOfDay, end: now, options: .strictStartDate
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

    /// Most recent weight sample (smart scale writes these), in pounds.
    public func latestBodyMassLb() async throws -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        do {
            return try await descriptor.result(for: store).first?.quantity.doubleValue(for: .pound())
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined {
            return nil
        }
    }

    /// Mean of (active + resting) burn over the last `days` full days,
    /// skipping days with implausibly little data. Nil if there's no history.
    public func averageDailyBurnKcal(days: Int = 14, now: Date = .now) async throws -> Double? {
        let calendar = Calendar.current
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
        return fullDays.reduce(0, +) / Double(fullDays.count)
    }

    private func dailyTotals(
        _ identifier: HKQuantityTypeIdentifier, start: Date, end: Date
    ) async throws -> [Date: Double] {
        let inRange = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
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

    /// Weigh-ins over the trailing `days`, date-ascending, in pounds.
    public func bodyMassHistory(days: Int = 90, now: Date = .now) async throws -> [WeightTrend.Point] {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return [] }
        let inRange = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
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

    // MARK: - Water log

    private var waterSampleCache: [UUID: HKQuantitySample] = [:]

    public func logWater(oz: Double, date: Date = .now) async throws {
        let sample = HKQuantitySample(
            type: HKQuantityType(.dietaryWater),
            quantity: HKQuantity(unit: .fluidOunceUS(), doubleValue: oz),
            start: date, end: date
        )
        try await store.save(sample)
    }

    /// Today's water servings from all sources, newest first.
    public func todayWaterEntries(now: Date = .now) async throws -> [WaterLogEntry] {
        let startOfDay = Calendar.current.startOfDay(for: now)
        let inToday = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
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
        return samples.map {
            WaterLogEntry(id: $0.uuid, oz: $0.quantity.doubleValue(for: .fluidOunceUS()), date: $0.startDate)
        }
    }

    public func deleteWaterEntry(id: UUID) async throws {
        guard let sample = waterSampleCache.removeValue(forKey: id) else { return }
        try await store.delete(sample)
    }

    // MARK: - Food log (writes)

    /// Log an eating event as an HKCorrelation(.food) wrapping energy and
    /// sodium samples, named via metadata so the log can be listed later.
    public func logFood(name: String, kcal: Double, sodiumMg: Double, date: Date = .now) async throws {
        let metadata: [String: Any] = [HKMetadataKeyFoodType: name]
        var objects: Set<HKSample> = [
            HKQuantitySample(
                type: HKQuantityType(.dietaryEnergyConsumed),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                start: date, end: date
            )
        ]
        if sodiumMg > 0 {
            objects.insert(HKQuantitySample(
                type: HKQuantityType(.dietarySodium),
                quantity: HKQuantity(unit: .gramUnit(with: .milli), doubleValue: sodiumMg),
                start: date, end: date
            ))
        }
        let correlation = HKCorrelation(
            type: HKCorrelationType(.food),
            start: date, end: date,
            objects: objects,
            metadata: metadata
        )
        try await store.save(correlation)
    }

    /// Today's logged eating events, newest first. Caches the underlying
    /// correlations so entries can be deleted by id.
    private var correlationCache: [UUID: HKCorrelation] = [:]

    public func todayFoodEntries(now: Date = .now) async throws -> [FoodLogEntry] {
        let startOfDay = Calendar.current.startOfDay(for: now)
        let inToday = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.food), predicate: inToday)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let correlations: [HKCorrelation]
        do {
            correlations = try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined {
            return []
        }
        correlationCache = Dictionary(uniqueKeysWithValues: correlations.map { ($0.uuid, $0) })
        return correlations.map { correlation in
            FoodLogEntry(
                id: correlation.uuid,
                name: correlation.metadata?[HKMetadataKeyFoodType] as? String ?? "Food",
                kcal: correlation.total(.dietaryEnergyConsumed, unit: .kilocalorie()),
                sodiumMg: correlation.total(.dietarySodium, unit: .gramUnit(with: .milli)),
                date: correlation.startDate
            )
        }
    }

    /// Delete a logged entry (and its contained samples) by correlation UUID.
    public func deleteFoodEntry(id: UUID) async throws {
        guard let correlation = correlationCache.removeValue(forKey: id) else { return }
        try await store.delete(Array(correlation.objects) + [correlation])
    }

    // MARK: - Debug seeding

    #if DEBUG
    /// Simulator helper: writes plausible intake/burn/water samples so the
    /// meter has data. Call requestDebugSeedAuthorization() first — this
    /// assumes write access to the burn/weight types is already granted.
    public func seedSampleData(now: Date = .now) async throws {
        func sample(
            _ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double,
            hoursAgo: Double, spanningHours: Double = 0
        ) -> HKQuantitySample {
            let end = now.addingTimeInterval(-hoursAgo * 3600)
            let start = end.addingTimeInterval(-spanningHours * 3600)
            return HKQuantitySample(
                type: HKQuantityType(id),
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: start, end: end
            )
        }

        var samples = [
            // energy burn accrued so far today
            sample(.activeEnergyBurned, .kilocalorie(), 385, hoursAgo: 1, spanningHours: 5),
            sample(.basalEnergyBurned, .kilocalorie(), 1120, hoursAgo: 0, spanningHours: 14),
            // two glasses of water
            sample(.dietaryWater, .fluidOunceUS(), 12, hoursAgo: 5),
            sample(.dietaryWater, .fluidOunceUS(), 12, hoursAgo: 1),
        ]
        // a month of daily weigh-ins drifting 202 → 200 lb with scale noise
        let wobble: [Double] = [0.4, -0.3, 0.6, -0.5, 0.1, 0.3, -0.4]
        for day in 0...30 {
            let trend = 202.0 - (Double(day) / 30.0) * 2.0
            samples.append(sample(
                .bodyMass, .pound(), trend + wobble[day % wobble.count],
                hoursAgo: Double(30 - day) * 24 + 12
            ))
        }
        // three full days of burn history so the 14-day average has data
        for day in 1...3 {
            samples.append(sample(
                .activeEnergyBurned, .kilocalorie(), 500,
                hoursAgo: Double(day) * 24, spanningHours: 10
            ))
            samples.append(sample(
                .basalEnergyBurned, .kilocalorie(), 1800,
                hoursAgo: Double(day) * 24, spanningHours: 16
            ))
        }
        try await store.save(samples)

        // breakfast and lunch as named food correlations
        try await logFood(name: "Two eggs & toast", kcal: 420, sodiumMg: 610,
                          date: now.addingTimeInterval(-6 * 3600))
        try await logFood(name: "Chicken burrito", kcal: 680, sodiumMg: 940,
                          date: now.addingTimeInterval(-2 * 3600))
    }
    #endif
}

private extension HKCorrelation {
    func total(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) -> Double {
        objects(for: HKQuantityType(identifier))
            .compactMap { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: unit) }
            .reduce(0, +)
    }
}
#endif
