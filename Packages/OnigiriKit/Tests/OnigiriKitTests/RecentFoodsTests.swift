import Foundation
import Testing
@testable import OnigiriKit

struct RecentFoodsTests {
    private func entry(_ name: String, daysAgo: Double) -> FoodLogEntry {
        FoodLogEntry(
            id: UUID(), name: name, kcal: 100, sodiumMg: 50,
            date: Date(timeIntervalSince1970: 1_700_000_000 - daysAgo * 86_400)
        )
    }

    @Test func keepsNewestEntryPerName() {
        let recents = [
            entry("Coffee", daysAgo: 2),
            entry("Oatmeal", daysAgo: 1),
            entry("Coffee", daysAgo: 0.5),
        ].uniquedByName(limit: 10)
        #expect(recents.map(\.name) == ["Coffee", "Oatmeal"])
        #expect(recents[0].date > recents[1].date)
    }

    @Test func nameMatchingIgnoresCaseAndWhitespace() {
        let recents = [
            entry("Protein shake", daysAgo: 0.1),
            entry("  protein SHAKE ", daysAgo: 0.2),
            entry("Toast", daysAgo: 0.3),
        ].uniquedByName(limit: 10)
        #expect(recents.map(\.name) == ["Protein shake", "Toast"])
    }

    @Test func capsAtLimit() {
        let entries = (0..<15).map { entry("Food \($0)", daysAgo: Double($0)) }
        let recents = entries.uniquedByName(limit: 10)
        #expect(recents.count == 10)
        #expect(recents.first?.name == "Food 0")
        #expect(recents.last?.name == "Food 9")
    }

    @Test func sortsUnorderedInputNewestFirst() {
        let recents = [
            entry("Middle", daysAgo: 3),
            entry("Newest", daysAgo: 1),
            entry("Oldest", daysAgo: 6),
        ].uniquedByName(limit: 10)
        #expect(recents.map(\.name) == ["Newest", "Middle", "Oldest"])
    }
}
