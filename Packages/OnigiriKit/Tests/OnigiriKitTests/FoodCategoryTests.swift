import Testing
import Foundation
@testable import OnigiriKit

struct FoodCategoryTests {
    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: .now)!
    }

    @Test func slotsFollowTheDayParts() {
        #expect(FoodCategory.slot(for: date(hour: 5)) == .breakfast)
        #expect(FoodCategory.slot(for: date(hour: 10)) == .breakfast)
        #expect(FoodCategory.slot(for: date(hour: 11)) == .lunch)
        #expect(FoodCategory.slot(for: date(hour: 14)) == .lunch)
        #expect(FoodCategory.slot(for: date(hour: 15)) == .snack)
        #expect(FoodCategory.slot(for: date(hour: 17)) == .snack)
        #expect(FoodCategory.slot(for: date(hour: 18)) == .dinner)
        #expect(FoodCategory.slot(for: date(hour: 22)) == .dinner)
    }

    @Test func lateNightCountsAsSnack() {
        #expect(FoodCategory.slot(for: date(hour: 23)) == .snack)
        #expect(FoodCategory.slot(for: date(hour: 2)) == .snack)
        #expect(FoodCategory.slot(for: date(hour: 4)) == .snack)
    }

    @Test func logEntryInfersCategoryFromTimeWhenUnset() {
        let entry = FoodLogEntry(id: UUID(), name: "Eggs", kcal: 150, sodiumMg: 120, date: date(hour: 8))
        #expect(entry.category == .breakfast)
        let tagged = FoodLogEntry(id: UUID(), name: "Eggs", kcal: 150, sodiumMg: 120, date: date(hour: 8), category: .snack)
        #expect(tagged.category == .snack)
    }
}
