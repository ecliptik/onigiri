import Foundation
import Testing
@testable import OnigiriKit

struct DayNutritionTests {
    private func entry(_ name: String, nutrients: NutrientValues) -> FoodLogEntry {
        FoodLogEntry(
            id: UUID(), name: name, kcal: 100, sodiumMg: 50,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            nutrients: nutrients
        )
    }

    @Test func totalNutrientsSumsAcrossEntries() {
        var oatmeal = NutrientValues(carbsG: 27, proteinG: 5, fiberG: 4)
        oatmeal[.iron] = 1.5
        var coffee = NutrientValues(caffeineMg: 95)
        coffee[.potassium] = 116
        var eggs = NutrientValues(fatG: 10, cholesterolMg: 370, proteinG: 12)
        eggs[.iron] = 1.7

        let total = [
            entry("Oatmeal", nutrients: oatmeal),
            entry("Coffee", nutrients: coffee),
            entry("Eggs", nutrients: eggs),
        ].totalNutrients

        #expect(total.carbsG == 27)
        #expect(total.proteinG == 17)
        #expect(total.fatG == 10)
        #expect(total.fiberG == 4)
        #expect(total.caffeineMg == 95)
        #expect(total.cholesterolMg == 370)
        #expect(total[.iron] == 3.2)
        #expect(total[.potassium] == 116)
    }

    @Test func unloggedFieldsStayNilNotZero() {
        // "None recorded" and "zero grams" must stay distinguishable.
        let total = [
            entry("Water crackers", nutrients: NutrientValues(carbsG: 20)),
            entry("More crackers", nutrients: NutrientValues(carbsG: 10)),
        ].totalNutrients
        #expect(total.carbsG == 30)
        #expect(total.fatG == nil)
        #expect(total.sugarG == nil)
        #expect(total.micros.isEmpty)
    }

    @Test func emptyDayIsEmpty() {
        #expect([FoodLogEntry]().totalNutrients.isEmpty)
    }

    @Test func mineralVitaminGroupsPartitionAllCases() {
        // The detail screen renders these two groups; together they must
        // cover every micronutrient exactly once, in declaration order.
        #expect(Micronutrient.minerals + Micronutrient.vitamins == Micronutrient.allCases)
    }
}
