import Foundation
import Testing
@testable import OnigiriKit

struct NutrientValuesTests {
    @Test func decodesLegacyJSONWithoutMicros() throws {
        // Encodings from before micronutrients existed must still decode.
        let json = #"{"fatG":8,"proteinG":4.5}"#
        let values = try JSONDecoder().decode(NutrientValues.self, from: Data(json.utf8))
        #expect(values.fatG == 8)
        #expect(values.proteinG == 4.5)
        #expect(values.micros.isEmpty)
    }

    @Test func microsRoundTripThroughCodable() throws {
        var values = NutrientValues(fatG: 1)
        values[.potassium] = 300
        values[.vitaminD] = 10
        let data = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode(NutrientValues.self, from: data)
        #expect(decoded == values)
        #expect(decoded[.potassium] == 300)
        #expect(decoded[.vitaminD] == 10)
    }

    @Test func unknownMicroKeysSurviveARoundTrip() throws {
        // A key from a newer app version must not be dropped or trap.
        let json = #"{"micros":{"vitaminK":120}}"#
        let values = try JSONDecoder().decode(NutrientValues.self, from: Data(json.utf8))
        let data = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode(NutrientValues.self, from: data)
        #expect(decoded.micros["vitaminK"] == 120)
    }

    @Test func fatDetailAndCholesterolRoundTripAndScale() throws {
        let values = NutrientValues(
            saturatedFatG: 4, transFatG: 0.5,
            polyunsaturatedFatG: 1.5, monounsaturatedFatG: 2.5,
            cholesterolMg: 30, caffeineMg: 80
        )
        let decoded = try JSONDecoder().decode(
            NutrientValues.self, from: JSONEncoder().encode(values)
        )
        #expect(decoded == values)
        let doubled = decoded.scaled(by: 2) + NutrientValues(cholesterolMg: 10)
        #expect(doubled.saturatedFatG == 8)
        #expect(doubled.transFatG == 1)
        #expect(doubled.polyunsaturatedFatG == 3)
        #expect(doubled.monounsaturatedFatG == 5)
        #expect(doubled.cholesterolMg == 70)
        #expect(doubled.caffeineMg == 160)
    }

    @Test func scalingAndSummingIncludeMicros() {
        var a = NutrientValues()
        a[.calcium] = 100
        var b = NutrientValues()
        b[.calcium] = 50
        b[.iron] = 2
        let sum = a.scaled(by: 2) + b
        #expect(sum[.calcium] == 250)
        #expect(sum[.iron] == 2)
    }

    @Test func emptinessConsidersMicros() {
        var values = NutrientValues()
        #expect(values.isEmpty)
        values[.zinc] = 5
        #expect(!values.isEmpty)
    }
}
