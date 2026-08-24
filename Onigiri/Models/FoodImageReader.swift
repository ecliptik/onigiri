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
    /// Estimates — hosts caption them as such, and `refine` is what
    /// lets the person correct one without photographing the food again
    /// (`plans/PLAN-refine-with-context.md`). nil means NOT refinable,
    /// so a path opts out rather than every path opting in.
    case food(ScannedProduct, refine: RefineContext?)
    /// The screenshot showed SEVERAL foods — a menu section, a
    /// comparison table. Which row the user meant is unknowable, and
    /// guessing logs the wrong burger, so the host asks. Never produced
    /// for a camera still (PLAN-screenshot-nutrition Part C).
    case candidates([ParsedLabel])
    /// A photographed MENU whose items carry printed calories — a board
    /// over the counter, a card on the table. Dozens of rows, and the
    /// host opens the searchable picker — which since
    /// `plans/PLAN-multi-item-import.md` is what `.candidates` opens
    /// too, so both list-shaped outcomes land in one control.
    /// `source` is the restaurant the menu named itself after, when it
    /// did — so the picker can prefill rather than ask.
    case menu([MenuRow], source: String?)
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

/// Everything a REFINE needs to ask again: the prior answer, what the
/// reader knew when it produced that answer, and — for a vision-capable
/// remote provider — the picture itself.
///
/// Only ESTIMATES carry one. A `.label` outcome reports figures printed
/// on a panel, and correcting a misread is a different job from adding
/// context (`plans/PLAN-refine-with-context.md`).
struct RefineContext {
    let prior: FoodIntelligence.RefinedFood
    let grounding: FoodIntelligence.EstimateGrounding
    /// The ALREADY-DOWNSAMPLED image the cascade worked on, never the
    /// original bytes: the share extension has 220 MB for the decode,
    /// Vision AND the model, and jetsam has taken it mid-decode already
    /// (2026-08-16). `jpegForUpload` re-encodes from this on demand, and
    /// only for a provider that can see.
    let image: CGImage?
    let orientation: CGImagePropertyOrientation?
}

@MainActor
enum FoodImageReader {
    /// Words a published nutrition table cannot avoid. A menu board
    /// carries dish names and prices and none of these.
    private static let nutritionWords = [
        "calorie", "kcal", "cal.", "nutrition", "sodium", "protein",
        "carbohydrate", "saturated", "cholesterol", "serving size",
        "total fat", "dietary fiber",
        // NOT "allergen": plenty of menus carry an allergen notice and
        // no figures at all, and the guides that do have both say
        // "Cal." anyway.
    ]

    static func mentionsNutrition(_ transcript: [LabelObservation]) -> Bool {
        let text = transcript.map(\.text).joined(separator: " ").lowercased()
        return nutritionWords.contains { text.contains($0) }
    }

    /// `status` reports the current stage for a progress label; it fires
    /// on the main actor and may be ignored.
    static func read(
        _ image: UIImage,
        source: FoodImageSource = .camera,
        status: @MainActor (String) -> Void = { _ in }
    ) async -> FoodImageOutcome {
        gated(await cascade(image, source: source, status: status))
    }

    /// Every outcome leaves through the plausibility gate — ONE door, so
    /// a new branch of the cascade below cannot forget to be checked
    /// (`NutritionPlausibility`). A menu is exempt here and gated at the
    /// pick instead: `MenuRow.parsedLabel` is where a row becomes
    /// something loggable, and checking 113 rows nobody chose is work
    /// for nothing.
    private static func gated(_ outcome: FoodImageOutcome) -> FoodImageOutcome {
        switch outcome {
        case .label(let label):
            let checked = NutritionPlausibility.checked(label)
            for finding in checked.warnings {
                // `reason` carries the parsed FIGURE in prose ("2,500 kcal
                // in one serving isn't a food"), so it stays private while
                // the severity — which gate fired — stays public. A
                // debugger still shows both.
                imageLog.notice("image read \(finding.severity.rawValue, privacy: .public): \(finding.reason, privacy: .private)")
            }
            return .label(checked)
        case .food(let product, let refine):
            return .food(product.plausible(), refine: refine)
        case .candidates(let labels):
            return .candidates(labels.map(NutritionPlausibility.checked))
        case .menu, .nothing, .cancelled:
            return outcome
        }
    }

    private static func cascade(
        _ image: UIImage,
        source: FoodImageSource,
        status: @MainActor (String) -> Void
    ) async -> FoodImageOutcome {
        status("Analyzing photo…")
        // Vision needs legible text, not sensor resolution: a 48 MP
        // library pick decoded at full size spikes memory across the
        // whole cascade (stacked against the model's own footprint —
        // jetsam territory on older devices). The redraw also bakes
        // orientation upright, so Vision gets .up pixels.
        //
        // Detached, because this enum is MainActor and a plain call ran
        // the whole resample ON the main thread — the screenshot-import
        // path hands this full-resolution images, and a large one froze
        // the app behind the "Analyzing photo…" spinner it had just put
        // up (jpegForUpload's @concurrent lesson; audit, 2026-08-17).
        let image = await Task.detached(priority: .userInitiated) {
            image.downsampled(maxEdge: 3000)
        }.value
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
            //
            // Gated on the text MENTIONING nutrition, for the same
            // reason the screenshot read below is, and learned the hard
            // way twice. Refine exists to fill gaps in a panel that was
            // photographed badly; handed a restaurant menu with no
            // panel at all, the on-device 3B model answered anyway and
            // invented 211 kcal from prices. That satisfied the
            // `parsed.kcal != nil` gate below, which returned a
            // nameless one-item label and never let the MENU question
            // be asked — the photo came back as an empty Log Food sheet
            // (the user, 2026-08-16; the Console log shows exactly one
            // inference, then "Label parsed"). A remote model declined
            // to invent and the same photo worked, which is why this
            // looked like an Apple Intelligence problem and was not.
            if mentionsNutrition(result.transcript) {
                parsed = await FoodIntelligence.refine(
                    result.parsed, transcript: result.transcript)
                guard !Task.isCancelled else { return .cancelled }
            }
            // An imported image is usually a screenshot of a published
            // nutrition page, which carries the one thing a
            // photographed panel never does: the food's NAME. Read it —
            // and any values the geometry parser couldn't reach, since
            // a web table is not the FDA panel LabelParser was built
            // for. Printed values always win over the model's
            // (PLAN-screenshot-nutrition Part B).
            // …but ONLY when the text actually mentions nutrition. This
            // read reports PRINTED figures, so a picture with none to
            // report has nothing for it to do — and asked anyway, it
            // invents: a photographed restaurant menu came back as one
            // nameless 1,150 kcal food with four macros, which then
            // satisfied the calorie gate below and returned before
            // anything could ask whether the picture was a MENU (the
            // user, 2026-08-16). Cheap, deterministic, and it saves an
            // inference on every picture that was never a nutrition
            // page.
            if source == .imported, FoodIntelligence.isAvailable,
               mentionsNutrition(result.transcript) {
                status("Analyzing screenshot…")
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
        // No nutrition panel — but the picture may be a MENU whose items
        // carry printed calories, which calorie labeling now requires of
        // chains in much of the US.
        //
        // BEFORE the sign read below, and that order is the whole point:
        // `readFoodSign` is prompted to ESTIMATE and marks its answers
        // with the AI dot, so left first it would guess at numbers that
        // are printed right there — against the rule the rest of the app
        // runs on. This path is deterministic, uncapped, and works with
        // AI off (PLAN-menu-import).
        let boardItems = MenuBoardParser.parse(transcript)
        if boardItems.count > 1 {
            imageLog.notice("Menu board: \(boardItems.count) item(s)")
            // A printed-calorie board is read deterministically and no
            // model saw it, so there is no name to offer.
            return .menu(boardItems, source: nil)
        }
        // Exactly one priced dish is not a menu worth a picker — it is a
        // food, and it goes straight to the form.
        if let only = boardItems.first {
            imageLog.notice("Menu board: one item")
            return .label(only.parsedLabel)
        }
        // Still nothing printed — which is the ORDINARY case for a
        // restaurant menu, not the exception: US calorie labeling binds
        // chains of 20+ locations, so an independent's board carries
        // names, descriptions and prices and nothing else. Seven real
        // menus supplied 2026-08-16 had calories on none of them.
        //
        // So ask what the menu OFFERS — WITH a calorie estimate per
        // dish, in the one call. A list of bare names is not something
        // anyone can choose from: the number is the whole reason for
        // opening the list (the user, 2026-08-16). One prompt answering
        // thirty dishes also costs less than thirty prompts answering
        // one, which is what estimating-on-selection was.
        //
        // Gated on the transcript being BOARD-SIZED, and that gate earns
        // its keep on the common photo rather than the rare one: someone
        // at a table photographs the ONE dish they are ordering, and for
        // that picture this read can only come back short, be discarded,
        // and leave the sign read below to do the work — two inferences
        // and two waits where one was needed. A cropped item is a
        // handful of text runs; a menu is dozens.
        if FoodIntelligence.isAvailable, transcript.count >= 20 {
            status("Reading the menu…")
            let reading = await FoodIntelligence.readMenuDishes(transcript: transcript)
            let dishes = reading.dishes
            guard !Task.isCancelled else { return .cancelled }
            // Logged UNCONDITIONALLY, including zero: "did the model get
            // asked, and what did it say" is the question three rounds
            // of guessing could not answer from the UI alone.
            imageLog.notice("Menu dishes: \(dishes.count) from \(transcript.count) runs, engine \(AIProviderSettings.selected.rawValue, privacy: .public)")
            // A high bar on purpose. A shelf sign or a bakery case names
            // a few things and belongs to the sign read below, which
            // estimates them outright; only a long list is a MENU.
            if dishes.count >= 4 {
                return .menu(dishes.enumerated().map { index, dish in
                    MenuRow(
                        id: index, name: dish.name, section: dish.section,
                        serving: nil, kcal: dish.kcal, sodiumMg: nil,
                        nutrients: NutrientValues(), aiGenerated: dish.kcal != nil)
                }, source: reading.restaurant)
            }
        }
        // Two more things are worth asking, in this order, because they
        // answer different pictures.
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
                // Refinable against the very text that named it: "it's
                // the large one", "no glaze" (PLAN-refine-with-context).
                return .food(
                    only.parsedLabel.scannedProduct(),
                    refine: RefineContext(
                        prior: FoodIntelligence.RefinedFood(only),
                        grounding: .signText(transcript.map(\.text).joined(separator: "\n")),
                        image: cgImage, orientation: orientation))
            }
            // 2. No usable text — maybe it's a photo of the food itself
            //    (PLAN-identify-food).
            let food = await FoodIntelligence.identifyFood(photo: cgImage, orientation: orientation)
            guard !Task.isCancelled else { return .cancelled }
            if let food {
                imageLog.notice("Photo identified: \(food.name), \(food.components.count) components, \(food.kcal) kcal")
                // The case the refine step exists for: on-device, the
                // model never saw this photo — it decomposed classifier
                // labels into a TYPICAL serving. The note is the only
                // thing that can say this plate was undressed and half
                // eaten (PLAN-refine-with-context).
                return .food(
                    food.scannedProduct,
                    refine: RefineContext(
                        prior: FoodIntelligence.RefinedFood(food),
                        grounding: .classifierLabels(food.groundingLabels),
                        image: cgImage, orientation: orientation))
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
                : "Couldn't read a nutrition label — try a closer, straighter shot. Turn on AI in Settings to identify food from a photo.")
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
    /// Decode STRAIGHT to the target size, never full-size first.
    ///
    /// `UIImage(data:)` then `downsampled` has to materialise the whole
    /// picture: a 48 MP HEIC is ~190 MB as pixels, and a share extension
    /// is given 220 MB in total. That is not a tight fit, it is a
    /// guaranteed kill — jetsam took the extension 219 ms after launch,
    /// during the decode, before any of this file's code ran
    /// (2026-08-16, `per-process-limit`, on a Live Photo with an HDR
    /// gain map). ImageIO reads the header, then decodes once at the
    /// size asked for.
    ///
    /// `kCGImageSourceCreateThumbnailWithTransform` bakes the
    /// orientation upright, which is what the renderer used to do.
    static func downsampled(data: Data, maxEdge: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// Cap the long edge before Vision: OCR wants legible text, not
    /// sensor resolution. Draws through a renderer, which also bakes
    /// the orientation upright. Prefer `downsampled(data:maxEdge:)`
    /// when the bytes are still to hand — this one needs the full image
    /// decoded already.
    ///
    /// nonisolated: real CPU work run from a detached task (`cascade`),
    /// and the target's MainActor default would otherwise pin it — and
    /// the caller — to the main thread. UIGraphicsImageRenderer is
    /// documented thread-safe, unlike the old UIGraphicsBeginImageContext.
    nonisolated func downsampled(maxEdge: CGFloat) -> UIImage {
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
