import Foundation
import Testing
@testable import OnigiriKit

/// The picker's running note. Its job is that the list you are still
/// choosing from says what has already gone into the day — the app and
/// the share extension both render it, so the sentence is pinned here
/// rather than written twice.
struct MenuPickProgressTests {
    @Test func nothingLoggedSaysNothing() {
        #expect(MenuPickProgress.note(logged: []) == nil)
    }

    /// One item names itself — a count of one tells you less than the
    /// name does, and "Logged 1 items" is not English.
    @Test func oneItemNamesIt() {
        #expect(MenuPickProgress.note(logged: ["Greek Chicken"])
            == "Logged Greek Chicken. Choose another, or tap Done.")
    }

    /// Several items need BOTH: the count for how far along you are,
    /// the last name for whether the tap you just made took.
    @Test func severalItemsCountAndNameTheLast() {
        #expect(MenuPickProgress.note(logged: ["Greek Chicken", "Pita"])
            == "Logged 2 items, last Pita. Choose another, or tap Done.")
        #expect(MenuPickProgress.note(logged: ["A", "B", "C", "Fries"])
            == "Logged 4 items, last Fries. Choose another, or tap Done.")
    }

    /// The same dish twice is a real order (two sides of fries), not a
    /// duplicate to fold away — the count is of LOGS, not of names.
    @Test func theSameDishTwiceCountsTwice() {
        #expect(MenuPickProgress.note(logged: ["Fries", "Fries"])
            == "Logged 2 items, last Fries. Choose another, or tap Done.")
    }
}
