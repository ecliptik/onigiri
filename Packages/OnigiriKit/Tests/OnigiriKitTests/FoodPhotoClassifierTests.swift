import Testing
import Foundation
@testable import OnigiriKit

/// The pure half of the identify-food classifier: ordering, dedup, cap,
/// and label normalization. The Vision half (ClassifyImageRequest) is
/// exercised end to end by the app's --food-id-sample UI hook — same
/// split as LabelScan (Vision) vs LabelParser (pure).
struct FoodPhotoClassifierTests {

    @Test func ordersByConfidenceAndNormalizesIdentifiers() {
        let guesses = FoodPhotoClassifier.guesses(from: [
            ("green_salad", 0.4),
            ("Caesar_salad ", 0.9),
            ("vegetable", 0.6),
        ])
        #expect(guesses.map(\.label) == ["caesar salad", "vegetable", "green salad"])
        #expect(guesses.first?.confidence == 0.9)
    }

    @Test func dedupesLabelsThatNormalizeIdentically() {
        let guesses = FoodPhotoClassifier.guesses(from: [
            ("green_salad", 0.8),
            ("Green salad", 0.5),
            ("green_salad ", 0.3),
        ])
        #expect(guesses.count == 1)
        // The most confident spelling wins.
        #expect(guesses.first?.confidence == 0.8)
    }

    @Test func capsTheShortlist() {
        let raw = (0..<20).map { ("label_\($0)", Double(20 - $0) / 20) }
        #expect(FoodPhotoClassifier.guesses(from: raw).count == 8)
        #expect(FoodPhotoClassifier.guesses(from: raw, cap: 3).count == 3)
    }

    @Test func emptyAndBlankInputsProduceNothing() {
        #expect(FoodPhotoClassifier.guesses(from: []).isEmpty)
        #expect(FoodPhotoClassifier.guesses(from: [("  ", 0.9), ("_", 0.8)]).isEmpty)
    }
}
