import Testing
import Foundation
@testable import OnigiriKit

/// Envelope extraction is the part of the BYO-AI clients that breaks
/// when a provider moves its API — fixture-tested offline, no network.
struct AIChatClientTests {
    // MARK: Anthropic envelope

    @Test func anthropicExtractsTextBlock() throws {
        let fixture = """
        {"id":"msg_01","type":"message","role":"assistant","model":"claude-haiku-4-5",
         "content":[{"type":"text","text":"{\\"name\\":\\"Rice bowl\\",\\"kcal\\":320}"}],
         "stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":12}}
        """
        let data = try AnthropicClient.extractContent(from: Data(fixture.utf8))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["name"] as? String == "Rice bowl")
        #expect(obj?["kcal"] as? Double == 320)
    }

    @Test func anthropicJoinsMultipleTextBlocks() throws {
        let fixture = """
        {"content":[{"type":"text","text":"{\\"a\\":"},{"type":"text","text":"1}"}]}
        """
        let data = try AnthropicClient.extractContent(from: Data(fixture.utf8))
        #expect(String(data: data, encoding: .utf8) == "{\"a\":1}")
    }

    @Test func anthropicRejectsGarbage() {
        #expect(throws: AIChatError.self) {
            _ = try AnthropicClient.extractContent(from: Data("not json".utf8))
        }
    }

    @Test func anthropicRejectsEmptyContent() {
        let fixture = #"{"content":[{"type":"thinking","text":null}]}"#
        #expect(throws: AIChatError.self) {
            _ = try AnthropicClient.extractContent(from: Data(fixture.utf8))
        }
    }

    // MARK: OpenAI-compatible envelope

    @Test func openAIExtractsMessageContent() throws {
        let fixture = """
        {"id":"chatcmpl-1","object":"chat.completion","model":"gpt-4o-mini",
         "choices":[{"index":0,"message":{"role":"assistant",
         "content":"{\\"name\\":\\"Two eggs\\",\\"kcal\\":156}"},"finish_reason":"stop"}]}
        """
        let data = try OpenAICompatibleClient.extractContent(from: Data(fixture.utf8))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["name"] as? String == "Two eggs")
    }

    @Test func openAIRejectsMissingChoices() {
        #expect(throws: AIChatError.self) {
            _ = try OpenAICompatibleClient.extractContent(from: Data(#"{"choices":[]}"#.utf8))
        }
    }

    @Test func openAIRejectsNullContent() {
        let fixture = #"{"choices":[{"message":{"role":"assistant","content":null}}]}"#
        #expect(throws: AIChatError.self) {
            _ = try OpenAICompatibleClient.extractContent(from: Data(fixture.utf8))
        }
    }

    // MARK: Fence stripping (models wrap JSON in markdown despite orders)

    @Test func stripsJSONFence() {
        #expect(AIChat.stripFence("```json\n{\"a\":1}\n```") == "{\"a\":1}")
    }

    @Test func stripsBareFence() {
        #expect(AIChat.stripFence("```\n{\"a\":1}\n```") == "{\"a\":1}")
    }

    @Test func leavesUnfencedAlone() {
        #expect(AIChat.stripFence("  {\"a\":1}  ") == "{\"a\":1}")
    }

    @Test func fencedEnvelopeRoundTrips() throws {
        let fixture = """
        {"choices":[{"message":{"content":"```json\\n{\\"kcal\\":42}\\n```"}}]}
        """
        let data = try OpenAICompatibleClient.extractContent(from: Data(fixture.utf8))
        #expect(String(data: data, encoding: .utf8) == "{\"kcal\":42}")
    }

    // MARK: Provider config (defaults half — Keychain needs a host app)

    @Test func providerDefaultsToOnDevice() {
        #expect(AIProvider(rawValue: "nonsense") == nil)
        #expect(AIProvider(rawValue: "") == nil)
        // Absent/garbage stored value → .onDevice via the accessor's
        // nil-coalesce; asserting the enum contract it relies on.
        #expect(AIProvider.onDevice.rawValue == "onDevice")
    }

    @Test func modelDefaultsAreNonEmpty() {
        #expect(!AIProviderSettings.defaultAnthropicModel.isEmpty)
        #expect(!AIProviderSettings.defaultOpenAIModel.isEmpty)
    }

    // MARK: Token-cap parameter (gpt-5.4-nano 400'd on max_tokens)

    @Test func openAIGetsMaxCompletionTokens() {
        #expect(OpenAICompatibleClient.tokenParameterName(
            for: OpenAICompatibleClient.openAIBaseURL) == "max_completion_tokens")
    }

    @Test func localServersKeepMaxTokens() {
        #expect(OpenAICompatibleClient.tokenParameterName(
            for: URL(string: "http://192.168.1.20:11434/v1")!) == "max_tokens")
    }

    // MARK: Server error-message extraction

    @Test func extractsOpenAIErrorMessage() {
        let body = #"{"error":{"message":"Unsupported parameter: 'max_tokens' is not supported with this model. Use 'max_completion_tokens' instead.","type":"invalid_request_error"}}"#
        let message = AIChat.errorMessage(from: Data(body.utf8))
        #expect(message?.contains("max_completion_tokens") == true)
    }

    @Test func extractsAnthropicErrorMessage() {
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        #expect(AIChat.errorMessage(from: Data(body.utf8)) == "invalid x-api-key")
    }

    @Test func errorMessageNilOnGarbage() {
        #expect(AIChat.errorMessage(from: Data("<html>502</html>".utf8)) == nil)
        #expect(AIChat.errorMessage(from: Data(#"{"error":{}}"#.utf8)) == nil)
    }
}
