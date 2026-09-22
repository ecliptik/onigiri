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

    @Test func itemAmountsReadTheRightField() {
        let nutrients = NutrientValues(
            proteinG: 12.5, micros: [Micronutrient.iron.rawValue: 1.6])
        #expect(TrackedNutrient.sodium.itemAmount(sodiumMg: 850, nutrients: nutrients) == 850)
        #expect(TrackedNutrient.protein.itemAmount(sodiumMg: 850, nutrients: nutrients) == 12.5)
        #expect(TrackedNutrient.micro(.iron).itemAmount(sodiumMg: 850, nutrients: nutrients) == 1.6)
        #expect(TrackedNutrient.fiber.itemAmount(sodiumMg: 850, nutrients: nutrients) == 0,
                "missing nutrients read as 0, like sodium always has")
        #expect(TrackedNutrient.water.itemAmount(sodiumMg: 850, nutrients: nutrients) == nil,
                "water is a log, not a food fact")
    }

    @Test func captionUnitsKeepSodiumShorthand() {
        #expect(TrackedNutrient.sodium.captionUnit == "mg Na")
        #expect(TrackedNutrient.protein.captionUnit == "g Protein")
        #expect(TrackedNutrient.micro(.vitaminB12).captionUnit == "µg Vitamin B12")
    }

    @Test func firstFoodMetricSkipsWaterAndUnset() {
        #expect(TrackedNutrient.firstFoodMetric(slot1: "sodium", slot2: "water") == .sodium)
        #expect(TrackedNutrient.firstFoodMetric(slot1: "protein", slot2: "water") == .protein)
        #expect(TrackedNutrient.firstFoodMetric(slot1: "water", slot2: "fiber") == .fiber,
                "water is log-only — the food surfaces skip to the next slot")
        #expect(TrackedNutrient.firstFoodMetric(slot1: "none", slot2: "water") == .sodium,
                "nothing applicable falls back to the long-standing sodium")
    }
}
