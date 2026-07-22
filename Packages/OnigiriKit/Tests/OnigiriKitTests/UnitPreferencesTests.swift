import Foundation
import Testing
@testable import OnigiriKit

struct UnitPreferencesTests {
    // MARK: Resolution — explicit beats locale, garbage falls to auto

    @Test func explicitRawValuesWin() {
        let metric = Locale(identifier: "de_DE")
        #expect(WeightUnit.resolve("lb", locale: metric) == .pounds)
        #expect(WaterUnit.resolve("oz", locale: metric) == .fluidOunces)
        #expect(SodiumUnit.resolve("mg", locale: metric) == .milligrams)
        let us = Locale(identifier: "en_US")
        #expect(WeightUnit.resolve("kg", locale: us) == .kilograms)
        #expect(WaterUnit.resolve("ml", locale: us) == .milliliters)
        #expect(SodiumUnit.resolve("salt", locale: us) == .saltGrams)
    }

    @Test func unknownRawFallsBackToLocale() {
        let us = Locale(identifier: "en_US")
        #expect(WeightUnit.resolve("auto", locale: us) == .pounds)
        #expect(WeightUnit.resolve(nil, locale: us) == .pounds)
        #expect(WeightUnit.resolve("stones", locale: us) == .pounds)
    }

    @Test func weightFollowsMeasurementSystem() {
        #expect(WeightUnit.resolve(nil, locale: Locale(identifier: "en_US")) == .pounds)
        // UK body weight stays imperial (measurementSystem .uk).
        #expect(WeightUnit.resolve(nil, locale: Locale(identifier: "en_GB")) == .pounds)
        #expect(WeightUnit.resolve(nil, locale: Locale(identifier: "de_DE")) == .kilograms)
        #expect(WeightUnit.resolve(nil, locale: Locale(identifier: "en_AU")) == .kilograms)
    }

    @Test func waterIsMetricEverywhereButUS() {
        #expect(WaterUnit.resolve(nil, locale: Locale(identifier: "en_US")) == .fluidOunces)
        // UK drink packaging is metric even though body weight isn't.
        #expect(WaterUnit.resolve(nil, locale: Locale(identifier: "en_GB")) == .milliliters)
        #expect(WaterUnit.resolve(nil, locale: Locale(identifier: "fr_FR")) == .milliliters)
    }

    @Test func sodiumFollowsLabelingRegionNotMeasurementSystem() {
        #expect(SodiumUnit.resolve(nil, locale: Locale(identifier: "en_US")) == .milligrams)
        // Metric but labels sodium in mg — the case that rules out
        // resolving via measurementSystem.
        #expect(SodiumUnit.resolve(nil, locale: Locale(identifier: "en_AU")) == .milligrams)
        #expect(SodiumUnit.resolve(nil, locale: Locale(identifier: "de_DE")) == .saltGrams)
        #expect(SodiumUnit.resolve(nil, locale: Locale(identifier: "en_GB")) == .saltGrams)
        #expect(SodiumUnit.resolve(nil, locale: Locale(identifier: "nb_NO")) == .saltGrams)
    }

    // MARK: Conversion

    @Test func weightRoundTrips() {
        #expect(abs(WeightUnit.kilograms.fromLb(176.3698) - 80.0) < 0.001)
        #expect(abs(WeightUnit.kilograms.toLb(80.0) - 176.3698) < 0.001)
        #expect(WeightUnit.pounds.fromLb(150) == 150)
        #expect(WeightUnit.pounds.toLb(150) == 150)
        let there = WeightUnit.kilograms.fromLb(203.7)
        #expect(abs(WeightUnit.kilograms.toLb(there) - 203.7) < 1e-9)
    }

    @Test func waterMatchesHealthKitFluidOunce() {
        #expect(abs(WaterUnit.milliliters.fromOz(12) - 354.88235475) < 0.001)
        #expect(abs(WaterUnit.milliliters.toOz(500) - 16.907) < 0.001)
        #expect(WaterUnit.fluidOunces.fromOz(64) == 64)
    }

    @Test func saltIsSodiumTimesTwoPointFive() {
        #expect(abs(SodiumUnit.saltGrams.fromMg(2300) - 5.75) < 1e-9)
        #expect(abs(SodiumUnit.saltGrams.toMg(5.75) - 2300) < 1e-9)
        #expect(SodiumUnit.milligrams.fromMg(2300) == 2300)
        #expect(abs(SodiumUnit.saltGrams.toMg(1.0) - 400) < 1e-9)
    }

    // MARK: Labels

    @Test func labels() {
        #expect(WeightUnit.pounds.symbol == "lb")
        #expect(WeightUnit.kilograms.symbol == "kg")
        #expect(WeightUnit.kilograms.spoken == "kilograms")
        #expect(WaterUnit.milliliters.symbol == "mL")
        #expect(WaterUnit.milliliters.spoken(1) == "milliliter")
        #expect(WaterUnit.fluidOunces.spoken(12) == "ounces")
        #expect(SodiumUnit.saltGrams.symbol == "g")
        #expect(SodiumUnit.saltGrams.nutrientName == "Salt")
        #expect(SodiumUnit.milligrams.nutrientName == "Sodium")
        #expect(SodiumUnit.saltGrams.fractionDigits == 1)
        #expect(SodiumUnit.milligrams.fractionDigits == 0)
        #expect(SodiumUnit.saltGrams.spoken(3.2) == "grams")
    }
}
