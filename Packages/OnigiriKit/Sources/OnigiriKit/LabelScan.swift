// Vision is unavailable on the watch — the kit builds there without the
// scan wrapper (the parser itself is pure and platform-free).
#if canImport(Vision) && !os(watchOS)
import Vision
import CoreGraphics
import ImageIO

/// The OCR half of the label-scan pipeline: one photo in, the parser's
/// `[(text, box)]` transcript out. Kept beside `LabelParser` so the
/// request configuration and the fixture-capture script
/// (`scripts/dump-label-ocr.swift`) can't drift apart.
public enum LabelScan {
    /// Runs the app's OCR configuration: `.accurate`, language correction
    /// OFF — correction "fixes" label numerics ("0g" → "Og") and unit
    /// strings, which the parser's own fixups handle deterministically.
    public static func observations(
        from image: CGImage,
        orientation: CGImagePropertyOrientation? = nil
    ) async throws -> [LabelObservation] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        let results = try await request.perform(on: image, orientation: orientation)
        return results.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let rect = observation.boundingBox.cgRect
            return LabelObservation(
                text: candidate.string,
                x: rect.origin.x, y: rect.origin.y,
                w: rect.width, h: rect.height)
        }
    }
}
#endif
