import Foundation
import Testing
@testable import OnigiriKit

/// Pins the FIFO cache's head-index eviction (the 2026-07-16 audit's
/// O(n) removeFirst fix): oldest-INSERTED falls out at the limit,
/// re-storing an existing key neither duplicates nor evicts, and the
/// amortized compaction of the dead prefix keeps evicting correctly.
struct ProductCacheTests {
    private func product(_ code: String) -> ScannedProduct {
        ScannedProduct(barcode: code, name: code, kcal: 100, sodiumMg: nil,
                       servingDescription: "1 serving", nutrients: NutrientValues())
    }

    @Test func oldestInsertedFallsOutAtTheLimit() async {
        let cache = ProductCache()
        // The cache's limit is private — 200 mirrored here; if eviction
        // never fires these assertions catch that too (c0 would remain).
        for i in 0...200 {
            await cache.store(product("c\(i)"), for: "c\(i)")
        }
        #expect(await cache.product(for: "c0") == nil)
        #expect(await cache.product(for: "c1") != nil)
        #expect(await cache.product(for: "c200") != nil)
    }

    @Test func restoringAnExistingKeyRefreshesWithoutEvicting() async {
        let cache = ProductCache()
        for i in 0..<200 {
            await cache.store(product("c\(i)"), for: "c\(i)")
        }
        await cache.store(product("c0"), for: "c0")
        #expect(await cache.product(for: "c0") != nil)
        #expect(await cache.product(for: "c1") != nil)
    }

    @Test func evictionSurvivesTheCompactionBoundary() async {
        let cache = ProductCache()
        // 450 distinct keys crosses the head >= limit compaction; the
        // live window must stay exactly the most recent 200.
        for i in 0..<450 {
            await cache.store(product("c\(i)"), for: "c\(i)")
        }
        #expect(await cache.product(for: "c249") == nil)
        #expect(await cache.product(for: "c250") != nil)
        #expect(await cache.product(for: "c449") != nil)
    }
}
