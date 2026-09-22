import Foundation
import Testing
@testable import OnigiriKit

/// A shared link often names the restaurant before a single page is
/// read (the user, 2026-08-16).
struct MenuDocumentSourceTests {
    @Test func aHostNamesTheBusinessBehindTheDocument() {
        #expect(MenuDocumentReader.source(fromHost: "shakeshack.widen.net") == "Shakeshack")
        #expect(MenuDocumentReader.source(fromHost: "www.chick-fil-a.com") == "Chick Fil A")
        #expect(MenuDocumentReader.source(fromHost: "cava.com") == "Cava")
    }

    @Test func infrastructureIsNotARestaurant() {
        // The service hosting the file, not the business that owns it.
        #expect(MenuDocumentReader.source(fromHost: "s3.amazonaws.com") == nil)
        #expect(MenuDocumentReader.source(fromHost: "cdn.squarespace.com") == nil)
        #expect(MenuDocumentReader.source(fromHost: "widen.net") == nil)
    }
}
