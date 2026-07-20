import Foundation
import Security

/// Which engine answers the app's AI features. On-device is the default
/// and today's behavior (Apple Intelligence, app-side FoundationModels);
/// the rest are bring-your-own: the user's Anthropic or OpenAI key, or
/// an OpenAI-compatible server they run themselves (Ollama, LM Studio —
/// how Gemma/Qwen/etc. arrive). See plans/PLAN-byo-ai.md.
public enum AIProvider: String, CaseIterable, Sendable {
    case onDevice
    case anthropic
    case openAI
    case local

    /// Settings-picker copy. (The rawValues persist in defaults —
    /// display names can move, cases must not.)
    public var displayName: String {
        switch self {
        case .onDevice: "Apple Intelligence"
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .local: "Local AI"
        }
    }

    /// One-line Settings description per provider — the user's copy
    /// (2026-07-19), tight and parallel: same three verbs everywhere,
    /// one extra trust sentence only where it's true.
    public var providerDescription: String {
        switch self {
        case .onDevice:
            "Use Apple Intelligence on this iPhone to estimate nutrition, read labels, and identify food. Nothing leaves this iPhone."
        case .anthropic:
            "Use your Anthropic account to estimate nutrition, read labels, and identify food."
        case .openAI:
            "Use your OpenAI account to estimate nutrition, read labels, and identify food."
        case .local:
            "Use a local OpenAI-compatible service — Ollama or LM Studio, running Gemma, Qwen, or any model — to estimate nutrition, read labels, and identify food."
        }
    }

    /// The ONE caption an AI-filled form shows (the user's copy,
    /// 2026-07-20): "AI" leads so the provenance is unmistakable, the
    /// provider name says where the text went (the privacy policy
    /// discloses per provider). Every estimate string routes through
    /// here so copy can't drift.
    public var estimateCaption: String {
        "AI estimate from \(displayName) — review before saving."
    }

    /// The photo-identification variant.
    public var photoEstimateCaption: String {
        "AI photo estimate from \(displayName) — review and adjust."
    }
}

/// Provider selection + per-provider configuration. The split follows
/// the FDC key's precedent exactly: SECRETS live in the Keychain
/// (device-only, never in a backup, never in the export); everything
/// else (selection, model ids, base URL) is App Group defaults.
public enum AIProviderSettings {
    // MARK: Selection + non-secret config (defaults)

    /// The master switch — AI is entirely optional and OFF BY DEFAULT
    /// (the user, 2026-07-20: the privacy story leads; marketing says
    /// "off by default" and the app makes it true). OFF hides every AI
    /// affordance app-wide (estimates, label refinement, Identify
    /// Food, the Siri describe intent) regardless of the selected
    /// provider. Absent = OFF; the search hint row points fresh
    /// installs at the switch.
    public static let enabledKey = "aiEnabled"
    public static var enabled: Bool {
        SharedStore.defaults.bool(forKey: enabledKey)
    }

    /// The one-time "AI is available" hint's dismissal flag.
    public static let hintDismissedKey = "aiHintDismissed"

    public static let providerKey = "aiProvider"
    public static let anthropicModelKey = "aiAnthropicModel"
    public static let openAIModelKey = "aiOpenAIModel"
    public static let localModelKey = "aiLocalModel"
    public static let localBaseURLKey = "aiLocalBaseURL"
    public static let localVisionKey = "aiLocalVisionCapable"

    /// Cheap/fast tiers by default; free-text and user-editable —
    /// providers rename models, so nothing hardcode-gates on these.
    public static let defaultAnthropicModel = "claude-haiku-4-5"
    public static let defaultOpenAIModel = "gpt-4o-mini"

    public static var selected: AIProvider {
        AIProvider(rawValue: SharedStore.defaults.string(forKey: providerKey) ?? "") ?? .onDevice
    }

    public static var anthropicModel: String {
        nonEmpty(SharedStore.defaults.string(forKey: anthropicModelKey)) ?? defaultAnthropicModel
    }

    public static var openAIModel: String {
        nonEmpty(SharedStore.defaults.string(forKey: openAIModelKey)) ?? defaultOpenAIModel
    }

    /// No default: the local model id is whatever the server loads
    /// ("gemma3", "qwen2.5vl", …). Empty means unconfigured.
    public static var localModel: String {
        nonEmpty(SharedStore.defaults.string(forKey: localModelKey)) ?? ""
    }

    /// The OpenAI-compatible base ("http://mac-mini.local:11434/v1").
    /// nil when absent or unparseable — the provider counts as
    /// unconfigured and every AI affordance stays hidden.
    public static var localBaseURL: URL? {
        guard let raw = nonEmpty(SharedStore.defaults.string(forKey: localBaseURLKey)) else { return nil }
        return URL(string: raw)
    }

    /// Whether the local model takes images — a user statement, not a
    /// probe (servers don't advertise it). Off = Identify Food routes
    /// the classifier-label TEXT relay instead of the photo.
    public static var localVisionCapable: Bool {
        SharedStore.defaults.bool(forKey: localVisionKey)
    }

    /// Whether the current selection is usable at all — the app-side
    /// availability gate for every non-on-device provider (the
    /// on-device check needs FoundationModels and lives app-side).
    public static var selectedRemoteIsConfigured: Bool {
        switch selected {
        case .onDevice: false
        case .anthropic: !anthropicAPIKey.isEmpty
        case .openAI: !openAIAPIKey.isEmpty
        case .local: localBaseURL != nil && !localModel.isEmpty
        }
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: Secrets (Keychain — the FDC pattern)

    // One service, one account per provider. AfterFirstUnlockThisDeviceOnly:
    // encrypted at rest, readable after first unlock, never in a backup and
    // never off this device.
    private static let keychainService = "com.ecliptik.Onigiri.ai"
    public static let anthropicKeyAccount = "anthropicAPIKey"
    public static let openAIKeyAccount = "openAIAPIKey"
    /// Optional bearer for a reverse-proxied local server; stock Ollama
    /// needs none and an empty value sends NO Authorization header.
    public static let localTokenAccount = "localAIToken"

    public static var anthropicAPIKey: String { readSecret(anthropicKeyAccount) ?? "" }
    public static var openAIAPIKey: String { readSecret(openAIKeyAccount) ?? "" }
    public static var localAIToken: String { readSecret(localTokenAccount) ?? "" }

    /// Save (non-empty) or clear (empty). Trimmed like the FDC key.
    @discardableResult
    public static func saveSecret(_ raw: String, account: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            SecItemDelete(query(account) as CFDictionary)
            return true
        }
        // Upsert (update-then-add), never delete-then-add — the latter
        // races and drops item metadata.
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(account)
            add.merge(attributes) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readSecret(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
