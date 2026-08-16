import Foundation
import Testing
@testable import OnigiriKit

/// The share-extension hand-off. `deposit`/`take` need a real app-group
/// container and are exercised on device; what IS unit-testable here is
/// the part that takes untrusted input — the shared file's name, which
/// comes from whatever app did the sharing and goes on to become a path.
struct ShareInboxTests {
    @Test func aSharedNameCannotEscapeTheInboxDirectory() {
        #expect(!ShareInbox.safe("../../etc/passwd").contains(".."))
        #expect(!ShareInbox.safe("../../etc/passwd").contains("/"))
        #expect(!ShareInbox.safe("a/b/c").contains("/"))
        #expect(!ShareInbox.safe("nul\u{0}byte").contains("\u{0}"))
    }

    @Test func anOrdinaryNameSurvivesLegibly() {
        #expect(ShareInbox.safe("Kwik Trip Guide.pdf") == "Kwik-Trip-Guide")
        #expect(ShareInbox.safe("menu.PDF") == "menu")
        #expect(ShareInbox.safe("IMG_0421.HEIC") == "IMG-0421")
        #expect(ShareInbox.safe("photo.jpeg") == "photo")
        #expect(ShareInbox.safe("KT5_26_AN_STND.pdf") == "KT5-26-AN-STND")
    }

    /// A name that sanitizes to nothing still has to produce a filename.
    @Test func anUnusableNameFallsBackRatherThanEmpty() {
        #expect(ShareInbox.safe("") == "shared")
        #expect(ShareInbox.safe("///") == "shared")
        #expect(ShareInbox.safe(".pdf") == "shared")
    }

    @Test func aVeryLongNameIsBounded() {
        let long = String(repeating: "a", count: 500)
        #expect(ShareInbox.safe(long).count <= 48)
    }
}
