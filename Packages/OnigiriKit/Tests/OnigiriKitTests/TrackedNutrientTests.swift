import Testing
@testable import OnigiriKit

struct TrackedNutrientTests {
    @Test func keysRoundTripForEveryNutrient() {
        for nutrient in TrackedNutrient.all {
            #expect(TrackedNutrient(key: nutrient.key) == nutrient)
        }
        #expect(TrackedNutrient(key: "notANutrient") == nil)
    }

    @Test func groupsCoverEverythingOnce() {
        let all = TrackedNutrient.all
        #expect(all.count == Set(all.map(\.key)).count)
        // 2 general + 10 macros + 26 micros.
        #expect(all.count == 38)
    }

    @Test func modesAndUnitsMatchConvention() {
        #expect(TrackedNutrient.sodium.defaultMode == .limit)
        #expect(TrackedNutrient.sugar.defaultMode == .limit)
        #expect(TrackedNutrient.water.defaultMode == .goal)
        #expect(TrackedNutrient.fiber.defaultMode == .goal)
        #expect(TrackedNutrient.water.unitSymbol == "oz")
        #expect(TrackedNutrient.protein.unitSymbol == "g")
        #expect(TrackedNutrient.micro(.iron).unitSymbol == "mg")
        #expect(TrackedNutrient.micro(.vitaminB12).unitSymbol == "µg")
    }

    @Test func defaultTargetsArePositive() {
        for nutrient in TrackedNutrient.all {
            #expect(nutrient.defaultTarget > 0, "\(nutrient.key)")
        }
    }

    @Test func defaultEmojiCoversEveryNutrient() {
        for nutrient in TrackedNutrient.all {
            #expect(SharedStore.isCustomEmoji(nutrient.defaultEmoji), "\(nutrient.key)")
        }
        #expect(TrackedNutrient.sodium.defaultEmoji == "🧂")
        #expect(TrackedNutrient.water.defaultEmoji == "💧")
        #expect(TrackedNutrient.micro(.iron).defaultEmoji == "🪨")
        #expect(TrackedNutrient.micro(.vitaminC).defaultEmoji == "💊")
    }

    @Test func inlineNamesKeepHistoricCopy() {
        #expect(TrackedNutrient.sodium.inlineName == "sodium")
        #expect(TrackedNutrient.water.inlineName == "water")
        #expect(TrackedNutrient.fiber.inlineName == "Fiber")
    }
}
