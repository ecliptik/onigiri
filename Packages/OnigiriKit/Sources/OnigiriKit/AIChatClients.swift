import Foundation
import os

private nonisolated let aiLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "ai-client")

/// Errors from the bring-your-own-AI chat clients. Callers treat every
/// one the same way — log and fall back to the deterministic path — but
/// the Settings connection test surfaces them to the user.
public enum AIChatError: Error, LocalizedError {
    case badURL
    /// Status code plus the server's own error message when one could
    /// be extracted — a bare "status 400" sent the user hunting when
    /// the body said exactly what was wrong (gpt-5.4-nano rejecting
    /// max_tokens, 2026-07-19).
    case badStatus(Int, String?)
    case badResponse
    case emptyContent

    public var errorDescription: String? {
        switch self {
        case .badURL:
            return "The server address isn't a valid URL."
        case .badStatus(let code, let message):
            if let message, !message.isEmpty {
                return "Status \(code): \(message)"
            }
            return code == 401 || code == 403
                ? "The API key was rejected (\(code))."
                : "The server answered with status \(code)."
        case .badResponse:
            return "The response wasn't in the expected format."
        case .emptyContent:
            return "The model returned no content."
        }
    }
}

/// One request shape both clients share: a system prompt, a user prompt,
/// and optionally a JPEG for vision-capable models. The reply is the
/// model's JSON text as raw bytes — prompts instruct JSON-only output,
/// and the extractors strip a markdown fence if the model added one.
/// Matching FoodIntelligence's manners: no retries, bounded timeout,
/// throw and let the caller fall back silently.
/// Public only for the two deadlines — the helpers below stay internal.
public enum AIChat {
    public static let timeout: TimeInterval = 30

    /// The deadline to use when another engine is standing by. Hard
    /// offline already fails instantly (the OS knows there is no
    /// route), so the full 30 s only bites on a WEAK signal — which is
    /// the case that was reported, and half a minute of spinner before
    /// an on-device answer is not a fallback anyone wants.
    public static let fallbackTimeout: TimeInterval = 10

    static func session(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        return URLSession(configuration: config)
    }

    /// Models often wrap JSON in ```json fences despite instructions —
    /// strip one balanced fence; anything else is the caller's decode
    /// failure to handle.
    static func stripFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        trimmed = String(trimmed.dropFirst(3))
        if trimmed.lowercased().hasPrefix("json") { trimmed = String(trimmed.dropFirst(4)) }
        if let end = trimmed.range(of: "```", options: .backwards) {
            trimmed = String(trimmed[..<end.lowerBound])
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func data(for request: URLRequest, timeout: TimeInterval = timeout) async throws -> Data {
        let (data, response) = try await session(timeout: timeout).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIChatError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = errorMessage(from: data)
            aiLog.notice("AI request failed: status \(http.statusCode) — \(message ?? "no body")")
            throw AIChatError.badStatus(http.statusCode, message)
        }
        return data
    }

    /// Pull the human-readable message out of a provider error body.
    /// OpenAI(-compatible): {"error":{"message":…}}; Anthropic:
    /// {"type":"error","error":{"message":…}} — one extractor covers
    /// both. Trimmed: Settings shows it inline. (Fixture-tested.)
    static func errorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = obj["error"] as? [String: Any],
              let message = error["message"] as? String else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(200))
    }
}

/// Anthropic Messages API. No SDK — URLSession like every other client
/// in the kit.
public enum AnthropicClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// One content block in a message — text or an inline base64 image.
    /// A manual `Encodable` because the two cases have different JSON
    /// shapes ({"type":"text","text":…} vs {"type":"image","source":{…}})
    /// — the thing a `[String: Any]` + `JSONSerialization` body used to
    /// express by just building whichever dictionary was needed
    /// (health-check audit, 2026-09-14: replaced for the same reason the
    /// file's own comment already flags this area as fragile — the
    /// max_tokens/max_completion_tokens naming bug two doors down).
    enum ContentBlock: Encodable {
        case text(String)
        case image(mediaType: String, base64Data: String)

        private enum CodingKeys: String, CodingKey {
            case type, text, source
        }
        private enum SourceCodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let mediaType, let base64Data):
                try container.encode("image", forKey: .type)
                var source = container.nestedContainer(keyedBy: SourceCodingKeys.self, forKey: .source)
                try source.encode("base64", forKey: .type)
                try source.encode(mediaType, forKey: .mediaType)
                try source.encode(base64Data, forKey: .data)
            }
        }
    }

    struct Message: Encodable {
        let role: String
        let content: [ContentBlock]
    }

    struct MessageRequest: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]

        private enum CodingKeys: String, CodingKey {
            case model, system, messages
            case maxTokens = "max_tokens"
        }
    }

    public static func completeJSON(
        apiKey: String,
        model: String,
        system: String,
        user: String,
        imageJPEG: Data? = nil,
        maxTokens: Int = 1024,
        /// Shortened when a fallback engine is standing by.
        timeout: TimeInterval = AIChat.timeout
    ) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var content: [ContentBlock] = []
        if let imageJPEG {
            content.append(.image(mediaType: "image/jpeg", base64Data: imageJPEG.base64EncodedString()))
        }
        content.append(.text(user))
        let body = MessageRequest(
            model: model, maxTokens: maxTokens, system: system,
            messages: [Message(role: "user", content: content)])
        request.httpBody = try JSONEncoder().encode(body)
        return try extractContent(from: try await AIChat.data(for: request, timeout: timeout))
    }

    /// Envelope → the reply text as JSON bytes. Split out for the
    /// fixture tests — this is the part that breaks when the API moves.
    static func extractContent(from data: Data) throws -> Data {
        struct Envelope: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let content: [Block]
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw AIChatError.badResponse
        }
        let text = envelope.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty else { throw AIChatError.emptyContent }
        return Data(AIChat.stripFence(text).utf8)
    }
}

/// OpenAI's chat-completions API — and, via `baseURL`, every
/// OpenAI-compatible local runner (Ollama, LM Studio, llama.cpp
/// server). One client, two providers.
public enum OpenAICompatibleClient {
    public static let openAIBaseURL = URL(string: "https://api.openai.com/v1")!

    /// A message's `content` field: OpenAI accepts either a plain string
    /// or an array of typed parts — the union a `[String: Any]` body
    /// used to express with `Any`. (health-check audit, 2026-09-14.)
    enum ChatContent: Encodable {
        case text(String)
        case parts([ContentPart])

        func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let text):
                var container = encoder.singleValueContainer()
                try container.encode(text)
            case .parts(let parts):
                var container = encoder.unkeyedContainer()
                for part in parts { try container.encode(part) }
            }
        }
    }

    /// One part of a multipart `content` array — text or an image URL
    /// (a data: URI for an inline JPEG, same as a real one).
    enum ContentPart: Encodable {
        case text(String)
        case imageURL(String)

        private enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }
        private struct ImageURLBox: Encodable { let url: String }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .imageURL(let url):
                try container.encode("image_url", forKey: .type)
                try container.encode(ImageURLBox(url: url), forKey: .imageURL)
            }
        }
    }

    struct ChatMessage: Encodable {
        let role: String
        let content: ChatContent
    }

    /// A manual `encode(to:)` because the token-cap field's KEY NAME is
    /// itself dynamic per endpoint (`tokenParameterName(for:)`) — the
    /// one thing a fixed `CodingKeys` enum can't express, and exactly
    /// the field a naming mismatch already broke live once (see that
    /// function's own comment). A `DynamicCodingKey` keeps this the only
    /// place that's true; everything else here is ordinary `Encodable`.
    struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let maxTokensParameterName: String
        let maxTokens: Int

        private struct DynamicCodingKey: CodingKey {
            let stringValue: String
            init(_ stringValue: String) { self.stringValue = stringValue }
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { nil }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            try container.encode(model, forKey: DynamicCodingKey("model"))
            try container.encode(messages, forKey: DynamicCodingKey("messages"))
            try container.encode(maxTokens, forKey: DynamicCodingKey(maxTokensParameterName))
        }
    }

    public static func completeJSON(
        baseURL: URL,
        apiKey: String,
        model: String,
        system: String,
        user: String,
        imageJPEG: Data? = nil,
        maxTokens: Int = 1024,
        /// Shortened when a fallback engine is standing by.
        timeout: TimeInterval = AIChat.timeout
    ) async throws -> Data {
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Stock Ollama takes no auth; an empty key sends NO header
        // (some proxies reject an empty Bearer outright).
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let userContent: ChatContent
        if let imageJPEG {
            userContent = .parts([
                .imageURL("data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"),
                .text(user),
            ])
        } else {
            userContent = .text(user)
        }
        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: .text(system)),
                ChatMessage(role: "user", content: userContent),
            ],
            maxTokensParameterName: Self.tokenParameterName(for: baseURL),
            maxTokens: maxTokens)
        request.httpBody = try JSONEncoder().encode(body)
        return try extractContent(from: try await AIChat.data(for: request, timeout: timeout))
    }

    /// api.openai.com: `max_tokens` is legacy and 400s on the GPT-5
    /// family ("use 'max_completion_tokens' instead" — hit live with
    /// gpt-5.4-nano, 2026-07-19); the new name works on every current
    /// OpenAI model. Local runners are the reverse — Ollama and LM
    /// Studio honor `max_tokens` and may predate the new name — so
    /// each endpoint gets its own. (Tested.)
    static func tokenParameterName(for baseURL: URL) -> String {
        baseURL == openAIBaseURL ? "max_completion_tokens" : "max_tokens"
    }

    /// Envelope → the reply text as JSON bytes (fixture-tested).
    static func extractContent(from data: Data) throws -> Data {
        struct Envelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw AIChatError.badResponse
        }
        guard let text = envelope.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIChatError.emptyContent
        }
        return Data(AIChat.stripFence(text).utf8)
    }
}
