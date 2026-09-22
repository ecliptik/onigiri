import XCTest
import OnigiriKit
@testable import Onigiri

/// The unreachable-provider fallback (PLAN-ai-fallback), end to end and
/// WITHOUT a network: the Local provider is pointed at `127.0.0.1:1`,
/// where the connection is refused instantly. That is a genuine
/// `URLError.cannotConnectToHost` — the same class as no cell coverage,
/// which is what prompted the feature (the user, 2026-08-07) — so the
/// whole routing runs for real rather than against a stub.
///
/// Opt-in like the eval suite: it needs Apple Intelligence to be the
/// thing that answers, which means real on-device inference.
final class AIFallbackTests: XCTestCase {
    /// Port 1 is reserved (tcpmux) and nothing listens on it, so the
    /// connection is refused on the loopback interface immediately —
    /// no timeout, no network, deterministic in CI and on a plane.
    private let deadServer = "http://127.0.0.1:1/v1"

    private var savedProvider: String?
    private var savedEnabled: Bool?
    private var savedBaseURL: String?
    private var savedModel: String?
    private var savedFallback: Any?

    @MainActor
    private func requireFallbackRun() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ONIGIRI_AI_FALLBACK"] == "1",
            "Opt-in: pass TEST_RUNNER_ONIGIRI_AI_FALLBACK=1 (runs real on-device inference)"
        )
        try XCTSkipUnless(
            FoodIntelligence.onDeviceAvailable,
            "Apple Intelligence unavailable here — there is no engine to fall back TO, so this proves nothing"
        )
    }

    override func setUp() {
        let defaults = SharedStore.defaults
        savedProvider = defaults.string(forKey: AIProviderSettings.providerKey)
        savedEnabled = defaults.object(forKey: AIProviderSettings.enabledKey) as? Bool
        savedBaseURL = defaults.string(forKey: AIProviderSettings.localBaseURLKey)
        savedModel = defaults.string(forKey: AIProviderSettings.localModelKey)
        savedFallback = defaults.object(forKey: AIProviderSettings.fallbackOnDeviceKey)

        // A configured-but-unreachable Local provider.
        defaults.set(true, forKey: AIProviderSettings.enabledKey)
        defaults.set(AIProvider.local.rawValue, forKey: AIProviderSettings.providerKey)
        defaults.set(deadServer, forKey: AIProviderSettings.localBaseURLKey)
        defaults.set("nothing-listens-here", forKey: AIProviderSettings.localModelKey)
    }

    override func tearDown() {
        let defaults = SharedStore.defaults
        restore(savedProvider, AIProviderSettings.providerKey)
        restore(savedBaseURL, AIProviderSettings.localBaseURLKey)
        restore(savedModel, AIProviderSettings.localModelKey)
        if let savedEnabled {
            defaults.set(savedEnabled, forKey: AIProviderSettings.enabledKey)
        } else {
            defaults.removeObject(forKey: AIProviderSettings.enabledKey)
        }
        if let savedFallback {
            defaults.set(savedFallback, forKey: AIProviderSettings.fallbackOnDeviceKey)
        } else {
            defaults.removeObject(forKey: AIProviderSettings.fallbackOnDeviceKey)
        }
    }

    private func restore(_ value: String?, _ key: String) {
        if let value {
            SharedStore.defaults.set(value, forKey: key)
        } else {
            SharedStore.defaults.removeObject(forKey: key)
        }
    }

    /// The reported scenario: the provider can't be reached, and an
    /// estimate still arrives — from Apple Intelligence.
    @MainActor
    func testUnreachableProviderFallsBackToAppleIntelligence() async throws {
        try requireFallbackRun()
        SharedStore.defaults.set(true, forKey: AIProviderSettings.fallbackOnDeviceKey)
        XCTAssertTrue(FoodIntelligence.isAvailable, "a configured Local provider counts as available")

        let estimate = await FoodIntelligence.describeFood("half a cup of cooked white rice")
        let food = try XCTUnwrap(
            estimate,
            "An unreachable provider with Fallback on must still produce an estimate"
        )
        // The provenance half — captioning this answer "Local AI" would
        // be a lie, and the caption is the only thing that says where
        // the numbers came from.
        XCTAssertEqual(food.engine, .onDevice, "the caption must name the engine that ANSWERED")
        XCTAssertEqual(food.engine.estimateCaption, "AI estimate from Apple Intelligence — review before saving.")
        XCTAssertGreaterThan(food.kcal, 0)
    }

    /// The half that proves the switch does something: same dead server,
    /// Fallback OFF, no estimate at all.
    @MainActor
    func testFallbackOffLeavesTheProviderFailureAlone() async throws {
        try requireFallbackRun()
        SharedStore.defaults.set(false, forKey: AIProviderSettings.fallbackOnDeviceKey)

        let food = await FoodIntelligence.describeFood("half a cup of cooked white rice")
        XCTAssertNil(food, "With Fallback off an unreachable provider must simply fail")
    }

    /// The classifier's verdict is what routes the two cases apart, and
    /// it is pure — assert the boundary directly rather than inferring
    /// it from an inference run.
    func testTheRoutingBoundary() {
        XCTAssertTrue(AIReachability.isTransient(URLError(.cannotConnectToHost)))
        XCTAssertTrue(AIReachability.isTransient(URLError(.notConnectedToInternet)))
        // A rejected key must never be masked by the fallback.
        XCTAssertFalse(AIReachability.isTransient(AIChatError.badStatus(401, nil)))
    }
}
