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
        } catch let error as HKError where error.code == .errorNoData {
            return 0
        }
    }

    // MARK: - Debug seeding

    #if DEBUG
    /// Simulator helper: writes plausible intake/burn/water samples so the
    /// meter has data. Requests share access to energy-burn types that the
    /// real app never writes — debug builds only.
    public func seedSampleData(now: Date = .now) async throws {
        let burnTypes: Set<HKSampleType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
        ]
        try await store.requestAuthorization(
            toShare: Self.shareTypes.union(burnTypes), read: Self.readTypes
        )

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

        let mg = HKUnit.gramUnit(with: .milli)
        let samples = [
            // breakfast and lunch
            sample(.dietaryEnergyConsumed, .kilocalorie(), 420, hoursAgo: 6),
            sample(.dietarySodium, mg, 610, hoursAgo: 6),
            sample(.dietaryEnergyConsumed, .kilocalorie(), 680, hoursAgo: 2),
            sample(.dietarySodium, mg, 940, hoursAgo: 2),
            // energy burn accrued so far today
            sample(.activeEnergyBurned, .kilocalorie(), 385, hoursAgo: 1, spanningHours: 5),
            sample(.basalEnergyBurned, .kilocalorie(), 1120, hoursAgo: 0, spanningHours: 14),
            // two glasses of water
            sample(.dietaryWater, .fluidOunceUS(), 12, hoursAgo: 5),
            sample(.dietaryWater, .fluidOunceUS(), 12, hoursAgo: 1),
        ]
        try await store.save(samples)
    }
    #endif
}
#endif
