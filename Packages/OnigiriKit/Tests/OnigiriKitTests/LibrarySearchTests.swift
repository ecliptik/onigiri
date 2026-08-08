import Testing
import Foundation
@testable import OnigiriKit

struct LibrarySearchTests {
    /// A stand-in for the two real row types (SwiftData models on the
    /// Foods tab, the Log sheet's Item struct) — the grouping rule is
    /// the thing under test, not either view's plumbing.
    private struct Row: LibrarySearchable {
        var searchName: String
        var searchCategory: String?
        var isStarred = false
        var isMealRow = false
        var isHistoryRow = false
        var searchRecency: Date = .distantPast
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(offset) * 86_400)
    }

    // MARK: - The complaint that started this

    /// The whole point: a food matches even though the caller was
    /// browsing Meals. Grouping never consults a scope, so there is no
    /// scope to leak in.
    @Test func aFoodMatchesWhileTheCallerIsBrowsingMeals() {
        let rows = [
            Row(searchName: "Nectarine"),
            Row(searchName: "Chicken & rice", isMealRow: true),
        ]
        let groups = LibrarySearch.groups(rows, query: "nectarine")
        #expect(groups.count == 1)
        #expect(groups[0].group == .foods)
        #expect(groups[0].items.map(\.searchName) == ["Nectarine"])
    }

    // MARK: - One home per row

    @Test func aStarredRowAppearsOnlyUnderFavorites() {
        let rows = [
            Row(searchName: "Nectarine Smoothie", isStarred: true, isMealRow: true),
            Row(searchName: "Nectarine"),
            Row(searchName: "Nectarine + Yogurt", isMealRow: true),
        ]
        let groups = LibrarySearch.groups(rows, query: "nectarine")
        #expect(groups.map(\.group) == [.favorites, .foods, .meals])
        #expect(groups[0].items.map(\.searchName) == ["Nectarine Smoothie"])
        #expect(groups[1].items.map(\.searchName) == ["Nectarine"])
        #expect(groups[2].items.map(\.searchName) == ["Nectarine + Yogurt"])
        // The count of rendered rows equals the count of matches — no
        // row is shown twice.
        #expect(groups.reduce(0) { $0 + $1.items.count } == 3)
    }

    @Test func groupPrecedenceIsFavoritesThenHistoryThenType() {
        #expect(LibrarySearch.group(Row(searchName: "a")) == .foods)
        #expect(LibrarySearch.group(Row(searchName: "a", isMealRow: true)) == .meals)
        #expect(LibrarySearch.group(Row(searchName: "a", isHistoryRow: true)) == .recentlyLogged)
        #expect(LibrarySearch.group(Row(searchName: "a", isStarred: true)) == .favorites)
        // Favorites wins over both type and history.
        #expect(
            LibrarySearch.group(
                Row(searchName: "a", isStarred: true, isMealRow: true, isHistoryRow: true)
            ) == .favorites
        )
    }

    @Test func historyRowsLandInRecentlyLogged() {
        let rows = [
            Row(searchName: "Nectarine"),
            Row(searchName: "Nectarine, large", isHistoryRow: true),
        ]
        let groups = LibrarySearch.groups(rows, query: "nectarine")
        #expect(groups.map(\.group) == [.foods, .recentlyLogged])
        #expect(groups[1].items.map(\.searchName) == ["Nectarine, large"])
    }

    // MARK: - Matching

    @Test func matchingIsCaseAndDiacriticInsensitive() {
        let rows = [Row(searchName: "Crème Brûlée")]
        #expect(LibrarySearch.groups(rows, query: "CREME").count == 1)
        #expect(LibrarySearch.groups(rows, query: "brulee").count == 1)
        #expect(LibrarySearch.groups(rows, query: "brûlée").count == 1)
    }

    @Test func categoryTextMatchesSoSnackPullsUpEverySnack() {
        let rows = [
            Row(searchName: "Almonds", searchCategory: "Snack"),
            Row(searchName: "Oatmeal", searchCategory: "Breakfast"),
        ]
        let groups = LibrarySearch.groups(rows, query: "snack")
        #expect(groups.count == 1)
        #expect(groups[0].items.map(\.searchName) == ["Almonds"])
    }

    @Test func surroundingWhitespaceIsIgnored() {
        let rows = [Row(searchName: "Nectarine")]
        #expect(LibrarySearch.groups(rows, query: "  nectarine  ").count == 1)
    }

    @Test func anEmptyQueryMatchesEverything() {
        let rows = [Row(searchName: "Nectarine"), Row(searchName: "Toast", isMealRow: true)]
        #expect(LibrarySearch.groups(rows, query: "").count == 2)
        #expect(LibrarySearch.groups(rows, query: "   ").count == 2)
    }

    @Test func aQueryThatMatchesNothingReturnsNoGroups() {
        let rows = [Row(searchName: "Nectarine"), Row(searchName: "Toast", isMealRow: true)]
        #expect(LibrarySearch.groups(rows, query: "zzqxvbn").isEmpty)
    }

    // MARK: - Ordering

    @Test func emptyGroupsAreDroppedAndOrderIsFixed() {
        let rows = [
            Row(searchName: "Nectarine, large", isHistoryRow: true),
            Row(searchName: "Nectarine Smoothie", isStarred: true),
        ]
        // Foods and Meals have no matches — they must not appear as
        // empty headers.
        #expect(LibrarySearch.groups(rows, query: "nectarine").map(\.group)
                == [.favorites, .recentlyLogged])
    }

    @Test func recencySortPutsTheMostRecentFirst() {
        let rows = [
            Row(searchName: "Apple pie", searchRecency: day(1)),
            Row(searchName: "Apple sauce", searchRecency: day(9)),
            Row(searchName: "Apple juice", searchRecency: day(5)),
        ]
        let groups = LibrarySearch.groups(rows, query: "apple", sortByRecency: true)
        #expect(groups[0].items.map(\.searchName) == ["Apple sauce", "Apple juice", "Apple pie"])
    }

    @Test func nameSortIgnoresRecency() {
        let rows = [
            Row(searchName: "Apple pie", searchRecency: day(1)),
            Row(searchName: "Apple sauce", searchRecency: day(9)),
            Row(searchName: "Apple juice", searchRecency: day(5)),
        ]
        let groups = LibrarySearch.groups(rows, query: "apple", sortByRecency: false)
        #expect(groups[0].items.map(\.searchName) == ["Apple juice", "Apple pie", "Apple sauce"])
    }

    @Test func equalRecencyFallsBackToName() {
        let rows = [
            Row(searchName: "Apple sauce", searchRecency: day(3)),
            Row(searchName: "Apple juice", searchRecency: day(3)),
        ]
        let groups = LibrarySearch.groups(rows, query: "apple", sortByRecency: true)
        #expect(groups[0].items.map(\.searchName) == ["Apple juice", "Apple sauce"])
    }

    @Test func rankingIsAppliedInsideEachGroupIndependently() {
        let rows = [
            Row(searchName: "Egg salad", isStarred: true, searchRecency: day(1)),
            Row(searchName: "Egg white", isStarred: true, searchRecency: day(7)),
            Row(searchName: "Egg noodles", searchRecency: day(2)),
            Row(searchName: "Egg drop soup", searchRecency: day(8)),
        ]
        let groups = LibrarySearch.groups(rows, query: "egg")
        #expect(groups[0].items.map(\.searchName) == ["Egg white", "Egg salad"])
        #expect(groups[1].items.map(\.searchName) == ["Egg drop soup", "Egg noodles"])
    }
}
