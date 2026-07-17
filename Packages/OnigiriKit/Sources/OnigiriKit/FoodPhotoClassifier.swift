// Vision is unavailable on the watch — the kit builds there without the
// classifier (identify-food is a phone flow; the pure guess filter is
// platform-free but useless without the camera, so it rides inside too).
#if canImport(Vision) && !os(watchOS)
import Vision
import CoreGraphics
import ImageIO

/// One classifier guess about what a food photo shows: a taxonomy label
/// ("salad", "banana bread") and the classifier's confidence. These are
/// DATA for the identify-food prompt — the classifier names the dish,
/// the language model decomposes it; neither sees what the other saw.
public struct FoodGuess: Sendable, Equatable {
    public let label: String
    public let confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}

/// The Vision half of the identify-food pipeline (PLAN-identify-food):
/// one photo in, a shortlist of confident scene labels out. Deliberately
/// does NOT decide "is this food" — a plate/bowl/table label is useful
/// context for the model, and the not-food gate lives in the
/// FoodIntelligence prompt where the whole shortlist is visible.
public enum FoodPhotoClassifier {
    /// Labels the model can work from. Empty means the classifier saw
    /// nothing it was confident about — the caller should fall back to
    /// its retry messaging, not the model.
    public static func classify(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation? = nil
    ) async throws -> [FoodGuess] {
        let request = ClassifyImageRequest()
        let results = try await request.perform(on: image, orientation: orientation)
        // High-precision operating point: better to hand the model three
        // labels it can trust than ten it can't.
        return guesses(from: results
            .filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
            .map { (identifier: $0.identifier, confidence: Double($0.confidence)) })
    }

    /// The pure half, unit-tested: order, dedup, cap, and normalize the
    /// taxonomy's underscore_identifiers into prompt-friendly words.
    static func guesses(
        from raw: [(identifier: String, confidence: Double)],
        cap: Int = 8
    ) -> [FoodGuess] {
        var seen = Set<String>()
        return raw
            .sorted { $0.confidence > $1.confidence }
            .compactMap { item in
                let label = item.identifier
                    .replacingOccurrences(of: "_", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                guard !label.isEmpty, seen.insert(label).inserted else { return nil }
                return FoodGuess(label: label, confidence: item.confidence)
            }
            .prefix(cap)
            .map { $0 }
    }
}
#endif
