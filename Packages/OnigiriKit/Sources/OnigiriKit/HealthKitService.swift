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
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryFiber),
        HKQuantityType(.dietarySugar),
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
        try await daySummary(for: now, now: now)
    }

    /// Totals for any calendar day — today ends at `now`, past days at midnight.
    public func daySummary(for date: Date, now: Date = .now) async throws -> DailyEnergySummary {
        let (start, end) = Self.dayRange(for: date, now: now)
        async let intake = sum(.dietaryEnergyConsumed, unit: .kilocalorie(), start: start, end: end)
        async let active = sum(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let resting = sum(.basalEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let sodium = sum(.dietarySodium, unit: .gramUnit(with: .milli), start: start, end: end)
        async let water = sum(.dietaryWater, unit: .fluidOunceUS(), start: start, end: end)
        return try await DailyEnergySummary(
            intakeKcal: intake,
            activeBurnKcal: active,
            restingBurnKcal: resting,
            sodiumMg: sodium,
            waterOz: water
        )
    }

    private static func dayRange(for date: Date, now: Date) -> (start: Date, end: Date) {
        let start = Calendar.current.startOfDay(for: date)
        return (start, min(start.addingTimeInterval(86400), max(now, start)))
    }

    private func sum(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date
    ) async throws -> Double {
        let inToday = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
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

    /// Per-day intake and burn totals over the trailing `days` (plus today),
    /// for the streak calendar. Days with no data at all are omitted.
    public func dailyEnergyTotals(days: Int = 92, now: Date = .now) async throws -> [DayEnergyTotals] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else {
            return []
        }
        async let intakeTotals = dailyTotals(.dietaryEnergyConsumed, start: start, end: now)
        async let activeTotals = dailyTotals(.activeEnergyBurned, start: start, end: now)
        async let basalTotals = dailyTotals(.basalEnergyBurned, start: start, end: now)
        let (intake, active, basal) = try await (intakeTotals, activeTotals, basalTotals)
        let allDays = Set(intake.keys).union(active.keys).union(basal.keys)
        return allDays.sorted().map { day in
            DayEnergyTotals(
                day: day,
                intakeKcal: intake[day] ?? 0,
                burnKcal: (active[day] ?? 0) + (basal[day] ?? 0)
            )
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

    /// Log an eating event as an HKCorrelation(.food) wrapping energy,
    /// sodium, and any known extended nutrients, named via metadata so the
    /// log can be listed later. Returns the correlation UUID for undo.
    /// Custom metadata key carrying the meal slot (FoodCategory rawValue).
    public static let mealCategoryMetadataKey = "OnigiriMealCategory"

    @discardableResult
    public func logFood(
        name: String,
        kcal: Double,
        sodiumMg: Double,
        nutrients: NutrientValues = NutrientValues(),
        category: FoodCategory? = nil,
        date: Date = .now
    ) async throws -> UUID {
        var metadata: [String: Any] = [HKMetadataKeyFoodType: name]
        if let category {
            metadata[Self.mealCategoryMetadataKey] = category.rawValue
        }
        var objects: Set<HKSample> = [
            HKQuantitySample(
                type: HKQuantityType(.dietaryEnergyConsumed),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                start: date, end: date
            )
        ]
        func insert(_ identifier: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double?) {
            guard let value, value > 0 else { return }
            objects.insert(HKQuantitySample(
                type: HKQuantityType(identifier),
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: date, end: date
            ))
        }
        insert(.dietarySodium, .gramUnit(with: .milli), sodiumMg)
        insert(.dietaryFatTotal, .gram(), nutrients.fatG)
        insert(.dietaryCarbohydrates, .gram(), nutrients.carbsG)
        insert(.dietaryProtein, .gram(), nutrients.proteinG)
        insert(.dietaryFiber, .gram(), nutrients.fiberG)
        insert(.dietarySugar, .gram(), nutrients.sugarG)
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

    /// Logged eating events for any calendar day, newest first.
    public func foodEntries(on date: Date, now: Date = .now) async throws -> [FoodLogEntry] {
        let (start, end) = Self.dayRange(for: date, now: now)
        let inToday = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
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
                date: correlation.startDate,
                category: (correlation.metadata?[Self.mealCategoryMetadataKey] as? String)
                    .flatMap(FoodCategory.init(rawValue:))
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

        var samples = [
            // energy burn accrued so far today
            sample(.activeEnergyBurned, .kilocalorie(), 385, start: todayAt(0.1), end: todayAt(0.6)),
            sample(.basalEnergyBurned, .kilocalorie(), 1120, start: todayAt(0), end: todayAt(0.95)),
            // two glasses of water
            sample(.dietaryWater, .fluidOunceUS(), 12, start: todayAt(0.4), end: todayAt(0.4)),
            sample(.dietaryWater, .fluidOunceUS(), 12, start: todayAt(0.9), end: todayAt(0.9)),
        ]
        // a month of daily weigh-ins drifting 202 → 200 lb with scale noise
        let wobble: [Double] = [0.4, -0.3, 0.6, -0.5, 0.1, 0.3, -0.4]
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

        // breakfast and lunch as named food correlations
        try await logFood(name: "Two eggs & toast", kcal: 420, sodiumMg: 610,
                          date: todayAt(0.25))
        try await logFood(name: "Chicken burrito", kcal: 680, sodiumMg: 940,
                          date: todayAt(0.75))
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

private extension HKCorrelation {
    func total(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) -> Double {
        objects(for: HKQuantityType(identifier))
            .compactMap { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: unit) }
            .reduce(0, +)
    }
}
#endif
