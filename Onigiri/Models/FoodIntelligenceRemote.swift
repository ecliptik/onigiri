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

    private static func completeRemote(
        system: String, user: String, imageJPEG: Data? = nil
    ) async -> Data? {
        do {
            switch AIProviderSettings.selected {
            case .onDevice:
                return nil
            case .anthropic:
                let key = AIProviderSettings.anthropicAPIKey
                guard !key.isEmpty else { return nil }
                return try await AnthropicClient.completeJSON(
                    apiKey: key, model: AIProviderSettings.anthropicModel,
                    system: system, user: user, imageJPEG: imageJPEG)
            case .openAI:
                let key = AIProviderSettings.openAIAPIKey
                guard !key.isEmpty else { return nil }
                return try await OpenAICompatibleClient.completeJSON(
                    baseURL: OpenAICompatibleClient.openAIBaseURL,
                    apiKey: key, model: AIProviderSettings.openAIModel,
                    system: system, user: user, imageJPEG: imageJPEG)
            case .local:
                guard let base = AIProviderSettings.localBaseURL else { return nil }
                let model = AIProviderSettings.localModel
                guard !model.isEmpty else { return nil }
                return try await OpenAICompatibleClient.completeJSON(
                    baseURL: base, apiKey: AIProviderSettings.localAIToken,
                    model: model, system: system, user: user, imageJPEG: imageJPEG)
            }
        } catch {
            log.notice("remote AI fell back: \(String(describing: error))")
            return nil
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
    }

    static func describeFoodRemote(_ description: String) async -> DescribedFood? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 500 else { return nil }
        let user = Prompts.describeUser(trimmed) + """
             Respond with ONLY a JSON object, no prose: {"name": string \
            (at most five words, title style), "kcal": number, \
            "sodiumMg": number, "serving": string (the portion restated \
            briefly, e.g. "1 bowl")}.
            """
        guard let estimate = decode(
            RemoteFoodEstimate.self,
            from: await completeRemote(system: Prompts.describeInstructions, user: user)
        ) else { return nil }
        let name = estimate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, estimate.kcal >= 0, estimate.kcal <= 5000,
              estimate.sodiumMg >= 0, estimate.sodiumMg <= 20_000 else { return nil }
        return DescribedFood(
            name: name,
            kcal: estimate.kcal,
            sodiumMg: estimate.sodiumMg,
            serving: estimate.serving.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Meal names

    private struct RemoteMealName: Decodable { let name: String }

    static func suggestMealNameRemote(for foodNames: [String]) async -> String? {
        let list = foodNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !list.isEmpty, list.joined().count < 500 else { return nil }
        let user = Prompts.mealNameUser(list) + """
             Respond with ONLY a JSON object, no prose: {"name": string \
            (a short, concrete meal name, at most four words)}.
            """
        guard let suggestion = decode(
            RemoteMealName.self,
            from: await completeRemote(system: Prompts.mealNameInstructions, user: user)
        ) else { return nil }
        let name = suggestion.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
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
    static func identifyFoodRemote(from guesses: [FoodGuess]) async -> IdentifiedFood? {
        let labels = guesses.map(\.label).filter { !$0.isEmpty }
        guard !labels.isEmpty, labels.joined().count < 500 else { return nil }
        let user = Prompts.identifyUser(labels) + identifyShape
        guard let food = parseIdentified(
            from: await completeRemote(system: Prompts.identifyInstructions, user: user)
        ) else { return nil }
        guard identifyContainmentHolds(
            name: food.name, componentNames: food.components.map(\.name), labels: labels
        ) else {
            log.notice("remote identify rejected: \(food.name) shares no words with labels")
            return nil
        }
        return food
    }

    /// Photo path for vision-capable providers: the model sees the
    /// image itself (the grounding), with the classifier labels as a
    /// second, possibly-wrong signal — so no label-containment guard.
    static func identifyFoodRemote(photoJPEG: Data, guesses: [FoodGuess]) async -> IdentifiedFood? {
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
        return parseIdentified(
            from: await completeRemote(system: system, user: user, imageJPEG: photoJPEG))
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

    /// Downscale + JPEG for upload economy (a label-free food shot
    /// doesn't need more than ~768 px for identification).
    static func jpegForUpload(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation?,
        maxEdge: CGFloat = 768
    ) -> Data? {
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

    static func refineRemote(_ parsed: ParsedLabel, transcript: [LabelObservation]) async -> ParsedLabel {
        guard refineNeeded(parsed) else { return parsed }
        let text = transcript.map(\.text).joined(separator: "\n")
        guard !text.isEmpty, text.count < 6_000 else { return parsed }
        let user = Prompts.refineUser(text) + """
            \n\nRespond with ONLY a JSON object, no prose — every field a \
            number exactly as printed or null when the label doesn't show \
            it: {"kcal": number|null, "sodiumMg": number|null (milligrams; \
            null when the label shows only salt), "fatG": number|null, \
            "carbsG": number|null, "proteinG": number|null, "fiberG": \
            number|null, "sugarG": number|null}.
            """
        guard let reading = decode(
            RemoteLabelReading.self,
            from: await completeRemote(
                system: Prompts.refineInstructions(basis: labelBasis(parsed)), user: user)
        ) else { return parsed }
        return merged(
            parsed,
            kcal: reading.kcal, sodiumMg: reading.sodiumMg,
            fatG: reading.fatG, carbsG: reading.carbsG,
            proteinG: reading.proteinG, fiberG: reading.fiberG,
            sugarG: reading.sugarG)
    }
}
