import Foundation
import Testing
@testable import OnigiriKit

/// The restaurant folded into a dish's name. The app and the share
/// extension both do it, and since 2026-09-20 the answer can arrive
/// after the dish is already on the confirm screen — so the rule is
/// applied repeatedly to the same name as the prompt is typed into, and
/// what it must never do is stack.
struct MenuSourceNameTests {
    @Test func theDishLeadsAndTheSourceTrails() {
        #expect(MenuSourceName.applied(to: "Greek Chicken", source: "CAVA")
            == "Greek Chicken (CAVA)")
    }

    /// No source, no brackets — most menus name no restaurant and the
    /// prompt is skipped.
    @Test func noSourceLeavesTheNameAlone() {
        #expect(MenuSourceName.applied(to: "Greek Chicken", source: "") == "Greek Chicken")
        #expect(MenuSourceName.applied(to: "Greek Chicken", source: "   ") == "Greek Chicken")
    }

    /// Typed by hand, so it arrives with whatever spacing the keyboard
    /// left behind.
    @Test func bothSidesAreTrimmed() {
        #expect(MenuSourceName.applied(to: "  Greek Chicken ", source: " CAVA ")
            == "Greek Chicken (CAVA)")
    }

    /// The whole reason this is a kit rule: the prompt stands OVER the
    /// confirm for a single shared item, so every keystroke re-applies
    /// it to the same dish, and once the editor has baked it into the
    /// name it must not earn a second one.
    @Test func applyingItTwiceChangesNothing() {
        let once = MenuSourceName.applied(to: "Greek Chicken", source: "CAVA")
        #expect(MenuSourceName.applied(to: once, source: "CAVA") == once)
    }

    /// Same, for a name the user typed themselves — they will not match
    /// the capitalisation they gave the prompt.
    @Test func anExistingSuffixIsRecognisedWhateverItsCase() {
        #expect(MenuSourceName.applied(to: "greek chicken (cava)", source: "CAVA")
            == "greek chicken (cava)")
    }

    /// A photographed panel carries no name at all. "(CAVA)" is not one
    /// either, so the restaurant stands in as the whole name rather than
    /// as a bracket around nothing.
    @Test func anUnnamedItemTakesTheSourceAsItsName() {
        #expect(MenuSourceName.applied(to: "", source: "CAVA") == "CAVA")
        #expect(MenuSourceName.applied(to: "", source: "") == "")
    }

    /// A different restaurant is a different suffix — the check is for
    /// THIS source, not for any bracket.
    @Test func aDifferentSourceStillApplies() {
        #expect(MenuSourceName.applied(to: "Fries (CAVA)", source: "Shake Shack")
            == "Fries (CAVA) (Shake Shack)")
    }
}
