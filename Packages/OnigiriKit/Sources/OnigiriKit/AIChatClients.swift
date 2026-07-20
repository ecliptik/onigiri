import Foundation
import os

// Logger is thread-safe; opt out of any MainActor default.
private nonisolated(unsafe) let aiLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "ai-client")

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
enum AIChat {
    static let timeout: TimeInterval = 30

    static func session() -> URLSession {
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

    static func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session().data(for: request)
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

    public static func completeJSON(
        apiKey: String,
        model: String,
        system: String,
        user: String,
        imageJPEG: Data? = nil,
        maxTokens: Int = 1024
    ) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var content: [[String: Any]] = []
        if let imageJPEG {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": imageJPEG.base64EncodedString(),
                ],
            ])
        }
        content.append(["type": "text", "text": user])
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": content]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try extractContent(from: try await AIChat.data(for: request))
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

    public static func completeJSON(
        baseURL: URL,
        apiKey: String,
        model: String,
        system: String,
        user: String,
        imageJPEG: Data? = nil,
        maxTokens: Int = 1024
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

        let userContent: Any
        if let imageJPEG {
            userContent = [
                [
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"],
                ],
                ["type": "text", "text": user],
            ]
        } else {
            userContent = user
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
        ]
        body[Self.tokenParameterName(for: baseURL)] = maxTokens
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try extractContent(from: try await AIChat.data(for: request))
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
