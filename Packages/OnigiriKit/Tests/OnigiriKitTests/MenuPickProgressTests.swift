import Foundation
import Testing
@testable import OnigiriKit

/// The picker's running note. Its job is that the list you are still
/// choosing from says what has already gone into the day — the app and
/// the share extension both render it, so the sentence is pinned here
/// rather than written twice.
struct MenuPickProgressTests {
    @Test func nothingLoggedSaysNothing() {
        #expect(MenuPickProgress.note([]) == nil)
    }

    /// One item names itself — a count of one tells you less than the
    /// name does, and "Logged 1 items" is not English.
    @Test func oneItemNamesIt() {
        #expect(MenuPickProgress.note([.logged("Greek Chicken")])
            == "Logged Greek Chicken. Choose another, or tap Done.")
    }

    /// Several items need BOTH: the count for how far along you are,
    /// the last name for whether the tap you just made took.
    @Test func severalItemsCountAndNameTheLast() {
        #expect(MenuPickProgress.note([.logged("Greek Chicken"), .logged("Pita")])
            == "Logged 2 items, last Pita. Choose another, or tap Done.")
        #expect(MenuPickProgress.note([.logged("A"), .logged("B"), .logged("C"), .logged("Fries")])
            == "Logged 4 items, last Fries. Choose another, or tap Done.")
    }

    /// The same dish twice is a real order (two sides of fries), not a
    /// duplicate to fold away — the count is of LOGS, not of names.
    @Test func theSameDishTwiceCountsTwice() {
        #expect(MenuPickProgress.note([.logged("Fries"), .logged("Fries")])
            == "Logged 2 items, last Fries. Choose another, or tap Done.")
    }

    // MARK: Saved, not logged

    /// A row saved to the library rather than logged gets its own verb —
    /// "Onigiri couldn't find a name here" is gone, but claiming a food
    /// was logged when it never touched Health would be its own kind of
    /// wrong (the user, 2026-08-29: "not necessarily log it").
    @Test func aSavedItemNamesItselfWithSaved() {
        #expect(MenuPickProgress.note([.saved("Greek Chicken")])
            == "Saved Greek Chicken. Choose another, or tap Done.")
    }

    /// The verb follows the LAST action, and the count counts every row
    /// taken off the list regardless of which action took it — a save
    /// is still progress through the menu.
    @Test func theVerbFollowsTheLastActionRegardlessOfEarlierOnes() {
        #expect(MenuPickProgress.note([.logged("Greek Chicken"), .saved("Pita")])
            == "Saved 2 items, last Pita. Choose another, or tap Done.")
        #expect(MenuPickProgress.note([.saved("Pita"), .logged("Greek Chicken")])
            == "Logged 2 items, last Greek Chicken. Choose another, or tap Done.")
    }
}
