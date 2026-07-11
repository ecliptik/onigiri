import Testing
@testable import OnigiriKit

struct LibraryDuplicateTests {
    @Test func matchesIgnoringCaseAndWhitespace() {
        #expect(LibraryDuplicate.nameMatches("Protein shake", "protein SHAKE"))
        #expect(LibraryDuplicate.nameMatches("  Protein shake ", "Protein shake"))
    }

    @Test func distinctNamesDoNotMatch() {
        #expect(!LibraryDuplicate.nameMatches("Protein shake", "Protein shake vanilla"))
        #expect(!LibraryDuplicate.nameMatches("Two eggs", "Two eggs & toast"))
        #expect(!LibraryDuplicate.nameMatches("", "Protein shake"))
    }
}
