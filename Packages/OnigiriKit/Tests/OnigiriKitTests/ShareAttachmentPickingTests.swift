import Testing
@testable import OnigiriKit

/// `ShareAttachmentPicking` — the pure half of `OnigiriShare`'s
/// image-attachment sniffing (health-check audit, 2026-09-14). The share
/// extension itself has no test target; this is what covers it.
struct ShareAttachmentPickingTests {
    @Test func picksAConcreteImageType() {
        let result = ShareAttachmentPicking.imageAttachmentIndex(
            registeredTypeIdentifiers: [["public.heic"]]
        )
        #expect(result?.providerIndex == 0)
        #expect(result?.identifier == "public.heic")
    }

    @Test func skipsTheAbstractImageIdentifier() {
        // A provider can register the abstract `public.image` umbrella
        // alongside (or instead of) a concrete type — only the concrete
        // one can actually be loaded via loadFileRepresentation.
        let result = ShareAttachmentPicking.imageAttachmentIndex(
            registeredTypeIdentifiers: [["public.image", "public.png"]]
        )
        #expect(result?.identifier == "public.png")
    }

    @Test func returnsNilWhenNoProviderHasAConcreteImageType() {
        let result = ShareAttachmentPicking.imageAttachmentIndex(
            registeredTypeIdentifiers: [["public.image"], ["com.adobe.pdf"]]
        )
        #expect(result == nil)
    }

    @Test func returnsNilForAnEmptyProviderList() {
        #expect(ShareAttachmentPicking.imageAttachmentIndex(registeredTypeIdentifiers: []) == nil)
    }

    @Test func picksTheFirstProviderInOrder() {
        // Order matters at the call site (a Safari share of a PDF page
        // can carry the file and its URL; the file provider comes
        // first) — pin that this stays a linear, first-match scan.
        let result = ShareAttachmentPicking.imageAttachmentIndex(
            registeredTypeIdentifiers: [["com.adobe.pdf"], ["public.jpeg"], ["public.png"]]
        )
        #expect(result?.providerIndex == 1)
        #expect(result?.identifier == "public.jpeg")
    }

    @Test func anUnknownIdentifierIsSkippedNotCrashed() {
        let result = ShareAttachmentPicking.imageAttachmentIndex(
            registeredTypeIdentifiers: [["not.a.real.uti", "com.compuserve.gif"]]
        )
        #expect(result?.identifier == "com.compuserve.gif")
    }
}
