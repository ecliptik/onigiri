import Foundation
import Testing
@testable import OnigiriKit

/// Filling resting burn for hours the watch wasn't worn. The refusals
/// matter as much as the fills: this arithmetic decides whether a day
/// earned its badge, so it must never invent a deficit.
struct RestingBurnFillTests {
    @Test func fullyCoveredDayIsUntouched() {
        let filled = RestingBurnFill.filled(
            recordedRestingKcal: 2_100, coveredHours: 24, hourlyRate: 87.5)
        #expect(filled == 2_100)
    }

    @Test func unwornHoursAreFilledAtTheRate() {
        // 16 hours worn at ~87.5/h = 1,400 recorded; 8 unworn hours add 700.
        let filled = RestingBurnFill.filled(
            recordedRestingKcal: 1_400, coveredHours: 16, hourlyRate: 87.5)
        #expect(filled == 2_100)
    }

    /// The field case: a day that ends early on the charger should land
    /// near a fully-worn day, not 500 kcal below it.
    @Test func aDayEndedEarlyLandsNearAFullDay() {
        let rate = RestingBurnFill.hourlyRate(totalRestingKcal: 2_109, totalCoveredHours: 24)
        let filled = RestingBurnFill.filled(
            recordedRestingKcal: 1_562, coveredHours: 18, hourlyRate: rate)
        #expect(filled > 2_000)
        #expect(filled < 2_200)
    }

    // MARK: Refusals

    @Test func thinCoverageIsNotExtrapolated() {
        // One recorded hour × 24 would fabricate a whole day's burn.
        let filled = RestingBurnFill.filled(
            recordedRestingKcal: 90, coveredHours: 1, hourlyRate: 87.5)
        #expect(filled == 90)
        let atBoundary = RestingBurnFill.filled(
            recordedRestingKcal: 260, coveredHours: 3, hourlyRate: 87.5)
        #expect(atBoundary == 260)
    }

    @Test func exactlyTheMinimumCoverageDoesFill() {
        let filled = RestingBurnFill.filled(
            recordedRestingKcal: 350, coveredHours: 4, hourlyRate: 87.5)
        #expect(filled == 350 + 20 * 87.5)
    }

    @Test func noCoverageFillsNothing() {
        // A day the watch never saw stays empty — filling 24 hours from
        // nothing would turn an untracked day into an earned one.
        let filled = RestingBurnFill.filled(
            recordedRestingKcal: 0, coveredHours: 0, hourlyRate: 87.5)
        #expect(filled == 0)
    }

    @Test func noRateFillsNothing() {
        let filled = RestingBurnFill.filled(
            recordedRestingKcal: 1_400, coveredHours: 16, hourlyRate: nil)
        #expect(filled == 1_400)
        let zeroRate = RestingBurnFill.filled(
            recordedRestingKcal: 1_400, coveredHours: 16, hourlyRate: 0)
        #expect(zeroRate == 1_400)
    }

    // MARK: The rate itself

    @Test func rateIsKcalPerWornHour() {
        #expect(RestingBurnFill.hourlyRate(totalRestingKcal: 2_400, totalCoveredHours: 24) == 100)
        #expect(RestingBurnFill.hourlyRate(totalRestingKcal: 0, totalCoveredHours: 24) == nil)
        #expect(RestingBurnFill.hourlyRate(totalRestingKcal: 2_400, totalCoveredHours: 0) == nil)
    }

    /// An in-progress day is filled against elapsed hours, not 24 — a
    /// day only a third gone must not be handed a full day's resting.
    @Test func partialDayFillsOnlyToTheHoursElapsed() {
        let filled = RestingBurnFill.filled(
            recordedRestingKcal: 350, coveredHours: 4, hourlyRate: 87.5, dayHours: 8)
        #expect(filled == 350 + 4 * 87.5)
    }
}
