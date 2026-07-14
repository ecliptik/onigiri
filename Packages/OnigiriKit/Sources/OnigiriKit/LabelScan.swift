// Vision is unavailable on the watch — the kit builds there without the
// scan wrapper (the parser itself is pure and platform-free).
#if canImport(Vision) && !os(watchOS)
import Vision
import CoreGraphics
import ImageIO

/// What a label photo yielded: the parse plus the transcript it came
/// from (the Foundation Models refinement pass re-reads the transcript).
public struct LabelScanResult: Sendable {
    public let parsed: ParsedLabel
    public let transcript: [LabelObservation]
}

/// The OCR half of the label-scan pipeline: one photo in, the parser's
/// `[(text, box)]` transcript out. Kept beside `LabelParser` so the
/// request configuration and the fixture-capture script
/// (`scripts/dump-label-ocr.swift`) can't drift apart.
public enum LabelScan {
    /// The whole pipeline. On iOS 26 the documents request runs first —
    /// its semantic table beats raw-geometry row association when the
    /// photo yields one (rendered graphics often don't; real photos do).
    /// Anything less falls back to the M2 text-recognition path.
    public static func scan(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation? = nil
    ) async throws -> LabelScanResult {
        if #available(iOS 26.0, macOS 26.0, *) {
            if let tableRows = try? await tableRows(from: image, orientation: orientation) {
                let tableObservations = LabelParser.observations(fromTableRows: tableRows)
                let parsed = LabelParser.parse(tableObservations)
                if !parsed.isEmpty {
                    return LabelScanResult(parsed: parsed, transcript: tableObservations)
                }
            }
        }
        let observations = try await observations(from: image, orientation: orientation)
        return LabelScanResult(parsed: LabelParser.parse(observations), transcript: observations)
    }

    /// iOS 26: the label as a semantic table — rows of cell transcripts,
    /// nil when the document model finds no plausible panel table.
    @available(iOS 26.0, macOS 26.0, *)
    static func tableRows(
        from image: CGImage,
        orientation: CGImagePropertyOrientation?
    ) async throws -> [[String]]? {
        let request = RecognizeDocumentsRequest()
        let results = try await request.perform(on: image, orientation: orientation)
        guard let document = results.first?.document,
              let table = document.tables.max(by: { $0.rows.count < $1.rows.count }),
              table.rows.count >= 3 else { return nil }
        return table.rows.map { row in
            row.map { $0.content.text.transcript }
        }
    }
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
