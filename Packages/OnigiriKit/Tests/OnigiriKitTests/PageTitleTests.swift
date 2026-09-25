import Testing
@testable import OnigiriKit

/// A shared page's title as the dish's name and the restaurant's. The
/// page's nutrition panel carries no name, so without this a shared
/// product page was named only when the model happened to supply one —
/// "Menu item" two shares in three (the user, 2026-09-24).
struct PageTitleTests {
    /// The two titles from that afternoon, verbatim.
    @Test func aProductPageNamesTheDishAndItself() {
        let sandwich = PageTitle.read(
            "Chick-fil-A® Chicken Sandwich | Chick-fil-A", host: "www.chick-fil-a.com")
        #expect(sandwich.item == "Chick-fil-A Chicken Sandwich")
        #expect(sandwich.site == "Chick-fil-A")

        let fries = PageTitle.read(
            "Waffle Potato Fries Nutrition and Ingredients | Chick-fil-A",
            host: "www.chick-fil-a.com")
        #expect(fries.item == "Waffle Potato Fries", "the page's furniture is not the dish")
        #expect(fries.site == "Chick-fil-A")
    }

    /// The site segment is found by the web address when it can be, so
    /// a title that LEADS with the brand still reads right.
    @Test func theSiteIsWhicheverSegmentTheAddressSpells() {
        let reading = PageTitle.read("Shake Shack - ShackBurger", host: "shakeshack.com")
        #expect(reading.site == "Shake Shack")
        #expect(reading.item == "ShackBurger")
    }

    /// A spaced hyphen separates; the hyphens inside a name do not.
    @Test func onlyASpacedHyphenSeparates() {
        let reading = PageTitle.read("Big Mac - McDonald's", host: nil)
        #expect(reading.item == "Big Mac")
        #expect(reading.site == "McDonald's")
        #expect(PageTitle.read("Chick-fil-A Nuggets").item == "Chick-fil-A Nuggets")
    }

    /// A title that names only a PAGE names no dish — nil, so the
    /// model's reading (or the confirm's own editor) supplies one.
    @Test func aGenericTitleNamesNothing() {
        #expect(PageTitle.read("Nutrition | CAVA", host: "cava.com").item == nil)
        #expect(PageTitle.read("Menu", host: nil).item == nil)
        #expect(PageTitle.read("", host: nil) == PageTitle.Reading(item: nil, site: nil))
    }
}
