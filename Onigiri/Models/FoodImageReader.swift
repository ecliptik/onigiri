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
    /// The screenshot showed SEVERAL foods — a menu section, a
    /// comparison table. Which row the user meant is unknowable, and
    /// guessing logs the wrong burger, so the host asks. Never produced
    /// for a camera still (PLAN-screenshot-nutrition Part C).
    case candidates([ParsedLabel])
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
        status("Reading photo…")
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
        // Kept out of the do-block: when there's no panel to parse, the
        // words Vision DID read are the next-best signal, and they have
        // to survive to the identify stage below.
        var transcript: [LabelObservation] = []
        // Likewise: a parse that found something but no CALORIES is the
        // last-resort payload at the very bottom of this function.
        var parsed = ParsedLabel()
        do {
            let result = try await LabelScan.scan(cgImage, orientation: orientation)
            transcript = result.transcript
            guard !Task.isCancelled else { return .cancelled }
            // iOS 26 + Apple Intelligence: the model fills whatever the
            // deterministic parse left blank — invisible, and every
            // model failure keeps the deterministic result.
            parsed = await FoodIntelligence.refine(result.parsed, transcript: result.transcript)
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
                imageLog.notice("Screenshot read: \(foods.count) food(s)")
                // A nutrition PAGE often lists a whole menu section.
                // Two or more readings means the row the user meant is
                // unknowable — ask rather than guess.
                if foods.count > 1 {
                    // Each candidate stands ALONE — do not merge the
                    // deterministic parse in. It can only represent one
                    // food, so on a multi-item table it has arbitrarily
                    // grabbed some row's numbers, and blank-filling
                    // would stamp those onto every candidate: four
                    // salads all reading 490 kcal (seen live
                    // 2026-07-24). Deterministic-wins is right for ONE
                    // food and wrong for a list.
                    return .candidates(foods.map(\.parsedLabel))
                }
                if let only = foods.first {
                    parsed = merged(parsed, filling: only)
                }
            }
            // CALORIES, not "anything at all". The old gate was
            // `!parsed.isEmpty`, and a single stray value satisfied it —
            // including the 0.0-where-it-meant-null that refine()'s own
            // comments describe as a known flake. On a bakery sign with
            // no panel that was enough to call it a label read, which
            // short-circuited every identification step below and opened
            // the form saying "Read the label, but not the calories"
            // (the user, 2026-08-02, on the very photo the sign read was
            // built for). A panel without calories isn't a panel.
            if parsed.kcal != nil {
                imageLog.notice("Label parsed: kcal \(parsed.kcal.map(String.init(describing:)) ?? "nil"), \(result.transcript.count) observations")
                return .label(parsed)
            }
            imageLog.notice("No calories parsed from \(result.transcript.count) observations — trying identification")
        } catch {
            imageLog.error("Label OCR failed: \(String(describing: error))")
            return .nothing(message: "Couldn't read that photo — try another.")
        }
        // No nutrition panel. Two things are still worth asking, in this
        // order, because they answer different pictures.
        if FoodIntelligence.isAvailable {
            status("Identifying food…")
            // 1. Does the picture SAY what the food is? A bakery-case
            //    card, a shelf sign, a menu board, a package front. The
            //    text names the dish outright, which no classifier label
            //    can, and it's the cheaper question (no image tokens, no
            //    Vision pass, works on every engine). This step is why a
            //    pasted bakery sign used to open a blank form: the name,
            //    the ingredients and the net weight were all read and
            //    then dropped on the floor (the user, 2026-08-02).
            let named = await FoodIntelligence.readFoodSign(transcript: transcript)
            guard !Task.isCancelled else { return .cancelled }
            imageLog.notice("Sign read: \(named.count) food(s)")
            // A case or a menu board advertises several at once — same
            // rule as a multi-item nutrition page: which one is
            // unknowable, so ask rather than log the wrong pastry.
            if named.count > 1 { return .candidates(named.map(\.parsedLabel)) }
            if let only = named.first {
                return .food(only.parsedLabel.scannedProduct())
            }
            // 2. No usable text — maybe it's a photo of the food itself
            //    (PLAN-identify-food).
            let food = await FoodIntelligence.identifyFood(photo: cgImage, orientation: orientation)
            guard !Task.isCancelled else { return .cancelled }
            if let food {
                imageLog.notice("Photo identified: \(food.name), \(food.components.count) components, \(food.kcal) kcal")
                return .food(food.scannedProduct)
            }
            imageLog.notice("Photo identify came up empty")
        }
        // AI off, unavailable, or it declined — but the text may still
        // plainly name the food. Hand over what it says and nothing
        // more: a name and a serving are transcription, not an estimate,
        // so they carry no provenance mark and no invented numbers. A
        // half-filled form beats a dead end (the user, 2026-08-02).
        if let named = SignText.namedFood(in: transcript) {
            imageLog.notice("Sign text named: \(named.name ?? "-")")
            return .label(named)
        }
        // Nothing identified it, but the parser did pull SOMETHING off
        // the image. Hand that over rather than nothing — the behavior
        // before the calorie gate above, now reached only as a last
        // resort instead of pre-empting identification.
        if !parsed.isEmpty {
            imageLog.notice("Partial label parse, nothing identified")
            return .label(parsed)
        }
        // Name the three things this camera actually does, so a failure
        // says which one to retry rather than implying it only reads
        // panels (the user, 2026-08-02).
        return .nothing(
            message: FoodIntelligence.isAvailable
                ? "Couldn't read a nutrition label, a name, or identify a food — try a closer, straighter shot."
                : "Couldn't read a nutrition label there — try a closer, straighter shot with the whole panel in frame. Turn on AI in Settings to estimate from a photo of the food or its sign.")
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
