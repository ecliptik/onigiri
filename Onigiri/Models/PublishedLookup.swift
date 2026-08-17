import Foundation
import OnigiriKit
import os

private let offerLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "published-offer")

/// The published figures for a food an ESTIMATE just named, when a
/// database plainly holds it (`plans/PLAN-nutrition-plausibility.md`,
/// Layer 4).
///
/// Accuracy comes from data, not from a better guess. The evals' worst
/// sodium miss is a Big Mac — the model says ~2,500 mg where McDonald's
/// publishes ~1,010 — and no amount of prompt work fixes a number the
/// model does not know. A lookup does.
///
/// It OFFERS and never substitutes (decided with the user, 2026-08-17).
/// The estimate stays exactly as it was until the person taps the row:
/// the match is a name match, not proof, and silently swapping numbers
/// under someone would make every estimate suspect.
///
/// Silent on every failure, by the same logic — this is an offer nobody
/// asked for, so it must cost nothing when it cannot be made.
@MainActor
enum PublishedLookup {
    /// One request where possible, two at most. Nil means "nothing worth
    /// offering", which covers lookups being off, no match, and any
    /// error alike.
    static func match(for name: String) async -> ScannedProduct? {
        // The user's own switch governs: an estimate is answerable
        // entirely on-device, and this is the only thing here that
        // leaves the phone.
        guard SharedStore.onlineLookups else { return nil }
        let estimate = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard estimate.count >= 3 else { return nil }
        let mode = SharedStore.textSearchMode

        // FDC first when it is configured: its rows carry the nutrient
        // table inline, so a match costs ONE request where OpenFoodFacts
        // costs two — and OFF's search rate limit is shared with the
        // searches the user actually typed.
        if mode != .openFoodFacts,
           let client = try? FoodDataCentralClient(apiKey: SharedStore.fdcAPIKey),
           let foods = try? await client.search(query: estimate, limit: 10),
           let product = PublishedNameMatch.best(
            for: estimate,
            among: foods.compactMap { food in
                food.kcalPer100g == nil ? nil : (food.description, food.per100gProduct)
            }) {
            offerLog.notice("published match from FDC for an estimate")
            return product
        }
        guard mode != .fdc else { return nil }

        let client = OpenFoodFactsClient()
        guard let rows = try? await client.search(query: estimate, limit: 10) else { return nil }
        // The OFF search index carries no nutrition at all, so the
        // candidate is chosen by NAME first and fetched second: one
        // detail request, never ten.
        guard let row = rows.first(where: {
            PublishedNameMatch.matches(estimate: estimate, candidate: $0.name)
        }), let product = try? await client.product(barcode: row.barcode),
              product.kcal != nil else { return nil }
        offerLog.notice("published match from OpenFoodFacts for an estimate")
        return product
    }
}
