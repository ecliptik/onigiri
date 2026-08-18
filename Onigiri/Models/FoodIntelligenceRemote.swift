import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import OnigiriKit

/// The bring-your-own-AI half of FoodIntelligence: the same four
/// capabilities served by the user's Anthropic key, OpenAI key, or
/// local OpenAI-compatible server (PLAN-byo-ai). No FoundationModels
/// here — kit clients and Codable DTOs only. Prompts come from
/// FoodIntelligence.Prompts (single-source with the on-device engine);
/// guards and merges are the shared helpers, so the engines can't
/// drift. Failure manners match on-device exactly: log, return
/// nil/unchanged, deterministic path takes over silently.
extension FoodIntelligence {
    // MARK: Dispatch

    /// Vision-capable = the photo itself can go to the model. Anthropic
    /// and OpenAI vision are API features; local depends on the served
    /// model, so it's the user's statement in Settings.
    static var remoteVisionCapable: Bool {
        switch AIProviderSettings.selected {
        case .onDevice: false
        case .anthropic, .openAI: true
        case .local: AIProviderSettings.localVisionCapable
        }
    }

    /// What a remote engine did with a request.
    ///
    /// The distinction is the whole point of the fallback: a provider
    /// that is UNREACHABLE is not a provider that said no. Every remote
    /// failure used to collapse to `nil`, so nothing downstream could
    /// tell "no cell coverage" from "the model refused" — and an
    /// identify-and-log in a dead zone died on the deterministic path
    /// with a perfectly good on-device model sitting idle (the user,
    /// 2026-08-07).
    enum RemoteAnswer<Value> {
        /// The provider replied. `nil` means the reply was unusable — a
        /// refusal, an unparseable shape, values the guards rejected.
        /// That is still an ANSWER, and no other engine second-guesses
        /// it.
        case answered(Value?)
        /// Couldn't get an answer now (`AIReachability.isTransient`), so
        /// a fallback engine may try. Also covers an unconfigured
        /// provider — there is nothing to ask.
        case unavailable
    }

    /// Is the fallback armed for THIS call? Used only to pick the
    /// deadline; whether it actually runs is the entry point's call.
    static var fallbackArmed: Bool {
        AIProviderSettings.selected != .onDevice && fallbackToOnDevice
    }

    private static func completeRemote(
        system: String, user: String, imageJPEG: Data? = nil
    ) async -> RemoteAnswer<Data> {
        // Shorter deadline when another engine is standing by: hard
        // offline fails instantly either way, so 30 s only ever bit the
        // weak-signal case.
        let timeout = fallbackArmed ? AIChat.fallbackTimeout : AIChat.timeout
        do {
            switch AIProviderSettings.selected {
            case .onDevice:
                return .answered(nil)
            case .anthropic:
                let key = AIProviderSettings.anthropicAPIKey
                guard !key.isEmpty else { return .unavailable }
                return .answered(try await AnthropicClient.completeJSON(
                    apiKey: key, model: AIProviderSettings.anthropicModel,
                    system: system, user: user, imageJPEG: imageJPEG,
                    timeout: timeout))
            case .openAI:
                let key = AIProviderSettings.openAIAPIKey
                guard !key.isEmpty else { return .unavailable }
                return .answered(try await OpenAICompatibleClient.completeJSON(
                    baseURL: OpenAICompatibleClient.openAIBaseURL,
                    apiKey: key, model: AIProviderSettings.openAIModel,
                    system: system, user: user, imageJPEG: imageJPEG,
                    timeout: timeout))
            case .local:
                guard let base = AIProviderSettings.localBaseURL else { return .unavailable }
                let model = AIProviderSettings.localModel
                guard !model.isEmpty else { return .unavailable }
                return .answered(try await OpenAICompatibleClient.completeJSON(
                    baseURL: base, apiKey: AIProviderSettings.localAIToken,
                    model: model, system: system, user: user, imageJPEG: imageJPEG,
                    timeout: timeout))
            }
        } catch {
            let transient = AIReachability.isTransient(error)
            // A REFUSED credential is `.unavailable`, not
            // `.answered(nil)`. Nothing was asked of any model, so there
            // is no answer for a fallback to second-guess — and
            // `.unavailable`'s own definition already covers this: "also
            // covers an unconfigured provider — there is nothing to
            // ask", which is exactly what a rejected key leaves you
            // with. Classed as an answer, it suppressed the on-device
            // fallback the user had switched ON precisely for this, so a
            // stale key returned NOTHING while a working engine sat idle
            // (audit, 2026-08-17).
            let rejected = AIReachability.isRejectedCredential(error)
            let verdict: String
            if transient {
                verdict = "unreachable — on-device may answer"
            } else if rejected {
                verdict = "credential refused — on-device may answer"
            } else {
                verdict = "answered, no fallback"
            }
            log.notice("remote AI fell back: \(String(describing: error)) (\(verdict))")
            if rejected { noteCredentialRejected() }
            return (transient || rejected) ? .unavailable : .answered(nil)
        }
    }

    /// Say ONCE, per launch, that the provider refused the key.
    ///
    /// The rest of this file fails silently on purpose — a model that
    /// declines is not news. A credential is a different class: it fails
    /// every time, for everything, until someone edits it, and the only
    /// other way to find out is opening Settings and tapping Test. The
    /// file's own rule already wanted this ("a key that silently stops
    /// working must not look identical to one that works").
    ///
    /// Routed through a hook rather than calling `ToastCenter` because
    /// this file also compiles into the share extension, which has no
    /// toast to show. There it stays nil and nothing happens.
    @MainActor static var onCredentialRejected: ((String) -> Void)?
    /// Re-armed when a key is edited (Settings) — a fresh key deserves a
    /// fresh warning if it is wrong too.
    @MainActor static var credentialNoticeShown = false

    private static func noteCredentialRejected() {
        let provider = AIProviderSettings.selected.displayName
        Task { @MainActor in
            guard !credentialNoticeShown else { return }
            credentialNoticeShown = true
            onCredentialRejected?(provider)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: Describe-it

    private struct RemoteFoodEstimate: Decodable {
        let name: String
        let kcal: Double
        let sodiumMg: Double
        let serving: String
        // Optional: a model that omits a macro degrades to a blank
        // form field, never a failed estimate.
        let fatG: Double?
        let carbsG: Double?
        let proteinG: Double?
        let fiberG: Double?
        let sugarG: Double?
    }

    static func describeFoodRemote(_ description: String) async -> RemoteAnswer<DescribedFood> {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 500 else { return .answered(nil) }
        let user = Prompts.describeUser(trimmed) + """
             Respond with ONLY a JSON object, no prose: {"name": string \
            (at most five words, title style), "kcal": number, \
            "sodiumMg": number, "serving": string (the portion restated \
            briefly, e.g. "1 bowl"), "fatG": number, "carbsG": number, \
            "proteinG": number, "fiberG": number, "sugarG": number — \
            grams for the described portion}.
            """
        guard case .answered(let data) = await completeRemote(
            system: Prompts.describeInstructions, user: user) else { return .unavailable }
        guard let estimate = decode(RemoteFoodEstimate.self, from: data) else { return .answered(nil) }
        let name = estimate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nutrients = estimateMacros(
            kcal: estimate.kcal,
            fatG: estimate.fatG, carbsG: estimate.carbsG,
            proteinG: estimate.proteinG, fiberG: estimate.fiberG,
            sugarG: estimate.sugarG)
        // The shared gate rather than local bounds — the on-device
        // engine runs the same check, and an estimate stands or falls
        // whole (see estimateHolds).
        guard !name.isEmpty, estimateHolds(
            kcal: estimate.kcal, sodiumMg: estimate.sodiumMg, nutrients: nutrients
        ) else { return .answered(nil) }
        return .answered(DescribedFood(
            name: name,
            kcal: estimate.kcal,
            sodiumMg: estimate.sodiumMg,
            serving: estimate.serving.trimmingCharacters(in: .whitespacesAndNewlines),
            nutrients: nutrients))
    }

    // MARK: Describe-meal

    private struct RemoteMealEstimate: Decodable {
        struct Component: Decodable {
            let name: String
            // Optional throughout except kcal: a model that omits a field
            // degrades to a blank form field, never a failed estimate.
            let portion: String?
            let kcal: Double
            let sodiumMg: Double?
            let fatG: Double?
            let carbsG: Double?
            let proteinG: Double?
            let fiberG: Double?
            let sugarG: Double?
        }
        let name: String
        let components: [Component]
    }

    static func describeMealRemote(_ description: String) async -> RemoteAnswer<DescribedMeal> {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 500 else { return .answered(nil) }
        let user = Prompts.describeMealUser(trimmed) + """
             Respond with ONLY a JSON object, no prose: {"name": string \
            (the meal, at most five words, title style), "components": \
            array of at most six {"name": string, "portion": string (this \
            component's portion, e.g. "1 cup"), "kcal": number, \
            "sodiumMg": number, "fatG": number, "carbsG": number, \
            "proteinG": number, "fiberG": number, "sugarG": number — \
            grams for that portion}}.
            """
        guard case .answered(let data) = await completeRemote(
            system: Prompts.describeMealInstructions, user: user) else { return .unavailable }
        guard let estimate = decode(RemoteMealEstimate.self, from: data) else { return .answered(nil) }
        let name = estimate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Same shared gate as on-device (name/kcal sanity, sodium clamp,
        // repeat collapse) — and the same six-component ceiling.
        let components = plausibleMealComponents(estimate.components.prefix(6).map {
            DescribedMeal.Component(
                name: $0.name, portion: $0.portion ?? "",
                kcal: $0.kcal, sodiumMg: $0.sodiumMg ?? 0,
                nutrients: estimateMacros(
                    kcal: $0.kcal,
                    fatG: $0.fatG, carbsG: $0.carbsG, proteinG: $0.proteinG,
                    fiberG: $0.fiberG, sugarG: $0.sugarG))
        })
        guard !name.isEmpty, !components.isEmpty else { return .answered(nil) }
        return .answered(DescribedMeal(name: name, components: components))
    }

    // MARK: Meal names

    private struct RemoteMealName: Decodable { let name: String }

    static func suggestMealNameRemote(for foodNames: [String]) async -> RemoteAnswer<String> {
        let list = foodNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !list.isEmpty, list.joined().count < 500 else { return .answered(nil) }
        let user = Prompts.mealNameUser(list) + """
             Respond with ONLY a JSON object, no prose: {"name": string \
            (a short, concrete meal name, at most four words)}.
            """
        guard case .answered(let data) = await completeRemote(
            system: Prompts.mealNameInstructions, user: user) else { return .unavailable }
        guard let suggestion = decode(RemoteMealName.self, from: data) else { return .answered(nil) }
        let name = suggestion.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Code-level twin of the on-device @Guide's "at most four
        // words" — a misbehaving remote server shouldn't dump a
        // paragraph into the name field (numeric fields already get
        // this parity treatment in describeFoodRemote).
        guard !name.isEmpty, name.count <= 60,
              name.split(separator: " ").count <= 6 else { return .answered(nil) }
        return .answered(name)
    }

    // MARK: Identify Food

    private struct RemotePhotoFood: Decodable {
        struct Component: Decodable {
            let name: String
            let portion: String
            let kcal: Double
            let sodiumMg: Double
        }
        let isFood: Bool
        let name: String
        let components: [Component]
    }

    private static let identifyShape = """
         Respond with ONLY a JSON object, no prose: {"isFood": boolean, \
        "name": string (at most five words; empty when isFood is false), \
        "components": array of at most six {"name": string, "portion": \
        string, "kcal": number, "sodiumMg": number} — the edible \
        components of one typical serving; empty when isFood is false}.
        """

    /// Text relay — any provider, no vision needed. Same containment
    /// guard as on-device: labels in, only labeled foods out.
    static func identifyFoodRemote(from guesses: [FoodGuess]) async -> RemoteAnswer<IdentifiedFood> {
        let labels = guesses.map(\.label).filter { !$0.isEmpty }
        guard !labels.isEmpty, labels.joined().count < 500 else { return .answered(nil) }
        let user = Prompts.identifyUser(labels) + identifyShape
        guard case .answered(let data) = await completeRemote(
            system: Prompts.identifyInstructions, user: user) else { return .unavailable }
        guard let food = parseIdentified(from: data) else { return .answered(nil) }
        guard identifyContainmentHolds(
            name: food.name, componentNames: food.components.map(\.name), labels: labels
        ) else {
            log.notice("remote identify rejected: \(food.name) shares no words with labels")
            return .answered(nil)
        }
        return .answered(food)
    }

    /// Photo path for vision-capable providers: the model sees the
    /// image itself (the grounding), with the classifier labels as a
    /// second, possibly-wrong signal — so no label-containment guard.
    static func identifyFoodRemote(photoJPEG: Data, guesses: [FoodGuess]) async -> RemoteAnswer<IdentifiedFood> {
        let labels = guesses.map(\.label).filter { !$0.isEmpty }
        let system = """
            You identify everyday foods and dishes from a photo. When it \
            shows edible food or drink, name the meal and break it into \
            the edible components of one typical full serving — include \
            the usual dressing, sauce, or condiments, and ignore \
            containers and scenery. Give commonsense portions and \
            nutrition per component — the person reviews and corrects \
            them. When nothing edible is in frame, set isFood to false \
            with no components.
            """
        let user = """
            Identify the food in the photo. A phone image classifier \
            guessed (most confident first, possibly wrong): \
            \(labels.joined(separator: ", ")).
            """ + identifyShape
        guard case .answered(let data) = await completeRemote(
            system: system, user: user, imageJPEG: photoJPEG) else { return .unavailable }
        return .answered(parseIdentified(from: data))
    }

    private static func parseIdentified(from data: Data?) -> IdentifiedFood? {
        guard let food = decode(RemotePhotoFood.self, from: data) else { return nil }
        let name = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = food.components
            .map { IdentifiedFood.Component(
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                portion: $0.portion.trimmingCharacters(in: .whitespacesAndNewlines),
                kcal: max(0, min($0.kcal, 3000)),
                sodiumMg: max(0, min($0.sodiumMg, 8000))) }
            .filter { !$0.name.isEmpty }
            .prefix(6)
        guard food.isFood, !name.isEmpty, !components.isEmpty else { return nil }
        return IdentifiedFood(name: name, components: Array(components))
    }

    /// Downscale + JPEG for upload. 1568 px is the long edge every
    /// current vision model accepts at standard image-token cost — the
    /// old 768 px "upload economy" guess threw away three quarters of
    /// the pixels and starved identification on mixed plates, which
    /// answered "vegetable stir fry" to anything it couldn't resolve
    /// (field report 2026-07-24). The high-resolution tier (Opus 4.7+,
    /// Sonnet 5) accepts 2576, but at up to ~3× the image tokens — a
    /// knob to turn only if 1568 still under-identifies.
    /// @concurrent: this is real CPU work (decode + resample + JPEG
    /// encode of a camera still) and its caller is MainActor-isolated —
    /// under approachable concurrency a plain nonisolated async func
    /// would STILL run its synchronous body on the caller's actor,
    /// freezing the "Identifying food…" spinner (2026-07-20 audit).
    @concurrent
    nonisolated static func jpegForUpload(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation?,
        maxEdge: CGFloat = 1568
    ) async -> Data? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxEdge / max(w, h))
        let outW = max(1, Int(w * scale)), outH = max(1, Int(h * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: outW, height: outH, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(outW), height: CGFloat(outH)))
        guard let scaled = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.7]
        if let orientation { props[kCGImagePropertyOrientation] = orientation.rawValue }
        CGImageDestinationAddImage(dest, scaled, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    // MARK: Screenshot nutrition import

    private struct RemoteScreenshotReading: Decodable {
        struct Item: Decodable {
            let name: String
            let serving: String?
            let kcal: Double?
            let sodiumMg: Double?
            let fatG: Double?
            let carbsG: Double?
            let proteinG: Double?
            let fiberG: Double?
            let sugarG: Double?
        }
        let foods: [Item]
    }

    /// Text relay — the OCR transcript, not the image. Works on every
    /// provider (no vision required), costs no image tokens, and OCR of
    /// rendered screen text is near-perfect anyway.
    static func readNutritionScreenshotRemote(_ text: String) async -> RemoteAnswer<[ScreenshotFood]> {
        let user = Prompts.screenshotUser(text) + """
            \n\nRespond with ONLY a JSON object, no prose — every \
            numeric field exactly as printed on the page, or null when \
            the page doesn't show it: {"foods": array of at most six \
            {"name": string, "serving": string, "kcal": number|null, \
            "sodiumMg": number|null (milligrams), "fatG": number|null, \
            "carbsG": number|null, "proteinG": number|null, "fiberG": \
            number|null, "sugarG": number|null}}. Return an empty array \
            when the text shows no nutrition figures.
            """
        guard case .answered(let data) = await completeRemote(
            system: Prompts.screenshotInstructions, user: user) else { return .unavailable }
        guard let reading = decode(RemoteScreenshotReading.self, from: data) else { return .answered(nil) }
        return .answered(plausibleScreenshotFoods(reading.foods.prefix(6).map { item in
            ScreenshotFood(
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                serving: (item.serving ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                kcal: item.kcal,
                sodiumMg: item.sodiumMg,
                nutrients: macroNutrients(
                    fatG: item.fatG, carbsG: item.carbsG, proteinG: item.proteinG,
                    fiberG: item.fiberG, sugarG: item.sugarG))
        }))
    }

    private struct RemoteMenuDishReading: Decodable {
        struct Item: Decodable {
            let name: String
            let section: String?
            /// A remote model answers "410", 410, or 410.0 depending on
            /// the day, and a strict Double? silently drops the first —
            /// which is a list of dishes with no calories beside them,
            /// the one thing the list exists to show.
            let kcal: Double?

            private enum CodingKeys: String, CodingKey { case name, section, kcal }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
                section = try? container.decodeIfPresent(String.self, forKey: .section)
                if let number = try? container.decodeIfPresent(Double.self, forKey: .kcal) {
                    kcal = number
                } else if let text = try? container.decodeIfPresent(String.self, forKey: .kcal) {
                    kcal = Double(text.filter { $0.isNumber || $0 == "." })
                } else {
                    kcal = nil
                }
            }
        }
        let dishes: [Item]
        let restaurant: String?
    }

    /// Text relay, like the reads above. Listing only — no numbers are
    /// requested, because a menu without calorie labeling prints none,
    /// and the one dish the person picks is estimated separately.
    static func readMenuSourceRemote(_ text: String) async -> RemoteAnswer<String?> {
        let system = FoodIntelligence.Prompts.menuSourceInstructions
        let user = FoodIntelligence.Prompts.menuSourceUser(text) + """


            Respond with ONLY a JSON object, no prose: \
            {"restaurant": string|null}.
            """
        struct Reading: Decodable { let restaurant: String? }
        switch await completeRemote(system: system, user: user) {
        case .unavailable: return .unavailable
        case .answered(let data):
            guard let data, let reading = try? JSONDecoder().decode(Reading.self, from: data)
            else { return .answered(nil) }
            return .answered(reading.restaurant)
        }
    }

    static func readMenuDishesRemote(_ text: String) async -> RemoteAnswer<FoodIntelligence.MenuReading> {
        let user = Prompts.menuDishUser(text) + """
            \n\nRespond with ONLY a JSON object, no prose: {"dishes": \
            array of at most thirty {"name": string, "section": \
            string|null, "kcal": number (estimated calories for one \
            serving as sold)}, "restaurant": string|null (the business's \
            name, never the word "Menu" alone)}. Never include a price, \
            an item number, or a description. Return an empty array when \
            the text is not a menu.
            """
        guard case .answered(let data) = await completeRemote(
            system: Prompts.menuDishInstructions, user: user) else { return .unavailable }
        guard let reading = decode(RemoteMenuDishReading.self, from: data) else { return .answered(nil) }
        return .answered(FoodIntelligence.MenuReading(
            dishes: plausibleMenuDishes(reading.dishes.prefix(30).map {
                FoodIntelligence.MenuDish(name: $0.name, section: $0.section, kcal: $0.kcal)
            }),
            restaurant: plausibleRestaurant(reading.restaurant)))
    }

    // MARK: Sign / menu / package-front read

    private struct RemoteSignReading: Decodable {
        struct Item: Decodable {
            let name: String
            let serving: String?
            let kcal: Double
            let sodiumMg: Double
            let fatG: Double?
            let carbsG: Double?
            let proteinG: Double?
        }
        let foods: [Item]
    }

    /// Text relay, like the screenshot read — the sign's words are the
    /// signal, and they cost no image tokens on any provider.
    static func readFoodSignRemote(_ text: String) async -> RemoteAnswer<[SignFood]> {
        let user = Prompts.signUser(text) + """
            \n\nRespond with ONLY a JSON object, no prose: {"foods": \
            array of at most six {"name": string (the food as the sign \
            titles it), "serving": string (one whole item as sold, e.g. \
            "1 roll (2.5 oz)"), "kcal": number, "sodiumMg": number \
            (milligrams), "fatG": number|null, "carbsG": number|null, \
            "proteinG": number|null — grams for that portion}}. Return \
            an empty array when the text names no food.
            """
        guard case .answered(let data) = await completeRemote(
            system: Prompts.signInstructions, user: user) else { return .unavailable }
        guard let reading = decode(RemoteSignReading.self, from: data) else { return .answered(nil) }
        return .answered(plausibleSignFoods(reading.foods.prefix(6).map { item in
            SignFood(
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                serving: (item.serving ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                kcal: item.kcal,
                sodiumMg: item.sodiumMg,
                nutrients: estimateMacros(
                    kcal: item.kcal,
                    fatG: item.fatG, carbsG: item.carbsG, proteinG: item.proteinG,
                    fiberG: nil, sugarG: nil))
        }, text: text))
    }

    // MARK: Label refinement

    private struct RemoteLabelReading: Decodable {
        let kcal: Double?
        let sodiumMg: Double?
        let fatG: Double?
        let carbsG: Double?
        let proteinG: Double?
        let fiberG: Double?
        let sugarG: Double?
    }

    static func refineRemote(_ parsed: ParsedLabel, transcript: [LabelObservation]) async -> RemoteAnswer<ParsedLabel> {
        guard refineNeeded(parsed) else { return .answered(parsed) }
        let text = transcript.map(\.text).joined(separator: "\n")
        guard !text.isEmpty, text.count < 6_000 else { return .answered(parsed) }
        let user = Prompts.refineUser(text) + """
            \n\nRespond with ONLY a JSON object, no prose — every field a \
            number exactly as printed or null when the label doesn't show \
            it: {"kcal": number|null, "sodiumMg": number|null (milligrams; \
            null when the label shows only salt), "fatG": number|null, \
            "carbsG": number|null, "proteinG": number|null, "fiberG": \
            number|null, "sugarG": number|null}.
            """
        guard case .answered(let data) = await completeRemote(
            system: Prompts.refineInstructions(basis: labelBasis(parsed)), user: user)
        else { return .unavailable }
        guard let reading = decode(RemoteLabelReading.self, from: data) else { return .answered(nil) }
        return .answered(merged(
            parsed,
            kcal: reading.kcal, sodiumMg: reading.sodiumMg,
            fatG: reading.fatG, carbsG: reading.carbsG,
            proteinG: reading.proteinG, fiberG: reading.fiberG,
            sugarG: reading.sugarG))
    }
}
