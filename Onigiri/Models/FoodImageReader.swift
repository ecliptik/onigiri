import UIKit
import OnigiriKit
import os

private let imageLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "scan")

/// What reading an image produced. The cases mirror ScanSheet's
/// callbacks exactly, so every door that can hand over a picture routes
/// through the host's existing plumbing.
enum FoodImageOutcome {
    /// A nutrition panel parsed — deterministic parse plus any AI
    /// blank-fill. Printed values, not estimates.
    case label(ParsedLabel)
    /// No panel in frame, but the model recognized the food itself.
    /// Estimates — hosts caption them as such.
    case food(ScannedProduct)
    /// Nothing usable; `message` is the user-facing retry copy.
    case nothing(message: String)
    /// Superseded or backed out of — deliver NOTHING. An orphaned
    /// completion re-presents a sheet the user already dismissed
    /// (2026-07-20 audit).
    case cancelled
}

/// The image cascade — OCR a nutrition panel, else identify the food —
/// shared by every door that can produce a picture: the scan sheet's
/// shutter and photo pick, and the paste/photo doors on the entry row
/// (PLAN-screenshot-nutrition). Extracted from ScanSheet so a pasted
/// screenshot reads EXACTLY the way a photographed label does: one path,
/// one set of failure messages, one place to change either.
/// Where the image came from. A camera still is a photographed panel;
/// an IMPORTED one (pasted or picked) is usually a screenshot of a
/// restaurant's nutrition page, which carries a name the panel never
/// does. Only the imported case pays for the screenshot read, so the
/// camera flow keeps its old cost and latency exactly.
enum FoodImageSource {
    case camera
    case imported
}

@MainActor
enum FoodImageReader {
    /// `status` reports the current stage for a progress label; it fires
    /// on the main actor and may be ignored.
    static func read(
        _ image: UIImage,
        source: FoodImageSource = .camera,
        status: @MainActor (String) -> Void = { _ in }
    ) async -> FoodImageOutcome {
        status("Reading label…")
        // Vision needs legible text, not sensor resolution: a 48 MP
        // library pick decoded at full size spikes memory across the
        // whole cascade (stacked against the model's own footprint —
        // jetsam territory on older devices). The redraw also bakes
        // orientation upright, so Vision gets .up pixels.
        let image = image.downsampled(maxEdge: 3000)
        guard let cgImage = image.cgImage else {
            return .nothing(message: "Couldn't read that photo — try another.")
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        do {
            let result = try await LabelScan.scan(cgImage, orientation: orientation)
            guard !Task.isCancelled else { return .cancelled }
            // iOS 26 + Apple Intelligence: the model fills whatever the
            // deterministic parse left blank — invisible, and every
            // model failure keeps the deterministic result.
            var parsed = await FoodIntelligence.refine(result.parsed, transcript: result.transcript)
            guard !Task.isCancelled else { return .cancelled }
            // An imported image is usually a screenshot of a published
            // nutrition page, which carries the one thing a
            // photographed panel never does: the food's NAME. Read it —
            // and any values the geometry parser couldn't reach, since
            // a web table is not the FDA panel LabelParser was built
            // for. Printed values always win over the model's
            // (PLAN-screenshot-nutrition Part B).
            if source == .imported, FoodIntelligence.isAvailable {
                status("Reading screenshot…")
                let foods = await FoodIntelligence.readNutritionScreenshot(
                    transcript: result.transcript)
                guard !Task.isCancelled else { return .cancelled }
                if let first = foods.first {
                    imageLog.notice("Screenshot read: \(foods.count) food(s), first \(first.name)")
                    parsed = merged(parsed, filling: first)
                }
            }
            if !parsed.isEmpty {
                imageLog.notice("Label parsed: kcal \(parsed.kcal.map(String.init(describing:)) ?? "nil"), \(result.transcript.count) observations")
                return .label(parsed)
            }
            imageLog.notice("Label parse empty from \(result.transcript.count) observations")
        } catch {
            imageLog.error("Label OCR failed: \(String(describing: error))")
            return .nothing(message: "Couldn't read that photo — try another.")
        }
        // The cascade (PLAN-identify-food): no nutrition panel in the
        // still, so maybe it's a photo of the food itself.
        guard FoodIntelligence.isAvailable else {
            return .nothing(
                message: "Couldn't read a nutrition panel there — try a closer, straighter shot with the whole panel in frame.")
        }
        status("Identifying food…")
        let food = await FoodIntelligence.identifyFood(photo: cgImage, orientation: orientation)
        guard !Task.isCancelled else { return .cancelled }
        if let food {
            imageLog.notice("Photo identified: \(food.name), \(food.components.count) components, \(food.kcal) kcal")
            return .food(food.scannedProduct)
        }
        imageLog.notice("Photo identify came up empty")
        return .nothing(
            message: "Couldn't read a nutrition panel or recognize a food there — try a closer shot.")
    }
}

private extension FoodImageReader {
    /// Deterministic values WIN — the geometry parser read them off the
    /// pixels, the model read them off a transcript. The screenshot
    /// read only fills blanks, exactly like refine()'s merge, and it is
    /// the sole source of the name (the parser never has one).
    static func merged(_ parsed: ParsedLabel, filling read: FoodIntelligence.ScreenshotFood) -> ParsedLabel {
        var result = parsed
        if result.name == nil, !read.name.isEmpty { result.name = read.name }
        if result.servingDescription == nil, !read.serving.isEmpty {
            result.servingDescription = read.serving
        }
        if result.kcal == nil { result.kcal = read.kcal }
        if result.sodiumMg == nil { result.sodiumMg = read.sodiumMg }
        result.nutrients = result.nutrients.fillingBlanks(from: read.nutrients)
        return result
    }
}

extension UIImage {
    /// Cap the long edge before Vision: OCR wants legible text, not
    /// sensor resolution. Draws through a renderer, which also bakes
    /// the orientation upright.
    func downsampled(maxEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return self }
        let scale = maxEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

extension CGImagePropertyOrientation {
    /// UIKit and ImageIO disagree on orientation raw values; Vision wants
    /// the ImageIO flavor.
    init(_ orientation: UIImage.Orientation) {
        self = switch orientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
