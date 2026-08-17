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

    /// One-line Settings description per provider — tight and parallel:
    /// same three verbs everywhere, and ONE sentence each (the user,
    /// 2026-08-17). The on-device case keeps its trust clause because
    /// staying on the phone is the whole difference; the remote cases
    /// say nothing about where data goes, since the fallback line
    /// below them already does.
    public var providerDescription: String {
        switch self {
        case .onDevice:
            "Apple Intelligence estimates nutrition, reads labels, and identifies food on this iPhone."
        case .anthropic:
            "Anthropic estimates nutrition, reads labels, and identifies food."
        case .openAI:
            "OpenAI estimates nutrition, reads labels, and identifies food."
        case .local:
            "A local OpenAI-compatible service — Ollama, LM Studio — estimates nutrition, reads labels, and identifies food."
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

    /// When the chosen provider can't be REACHED — no signal, DNS
    /// failure, a rate limit, an outage — answer with Apple
    /// Intelligence instead of failing (the user, 2026-08-07: an
    /// identify-and-log died in an area with no cell coverage while the
    /// on-device model sat idle).
    ///
    /// ON by default, unlike everything else AI. The privacy-first
    /// default doesn't apply here: a fallback sends LESS, not more —
    /// nothing leaves the device — and by the time this can fire the
    /// user has already opted into AI and picked a provider.
    ///
    /// Hence the explicit absent check: `defaults.bool(forKey:)` alone
    /// returns false for an unset key, which would ship a fresh install
    /// with exactly the behavior this fixes.
    public static let fallbackOnDeviceKey = "aiFallbackOnDevice"
    public static var fallbackToOnDevice: Bool {
        guard SharedStore.defaults.object(forKey: fallbackOnDeviceKey) != nil else { return true }
        return SharedStore.defaults.bool(forKey: fallbackOnDeviceKey)
    }

    /// Whether AI may ESTIMATE nutrition it cannot read — a described
    /// meal, an identified photo, a menu dish with no figures printed.
    /// Reading stays on either way: a scanned label, a nutrition
    /// screenshot and a menu's own printed calories are transcription,
    /// not guesswork, and switching estimates off must not cost them.
    ///
    /// ON by default, like the fallback and unlike everything else AI:
    /// by the time this can fire the user has already opted into AI, and
    /// an estimate is most of what the feature is for. Hence the
    /// explicit absent check — `bool(forKey:)` alone reads false for an
    /// unset key, which would ship every install with it off (the user,
    /// 2026-08-16: "turn them on by default").
    public static let estimateNutritionKey = "aiEstimateNutrition"
    public static var estimateNutrition: Bool {
        guard SharedStore.defaults.object(forKey: estimateNutritionKey) != nil else { return true }
        return SharedStore.defaults.bool(forKey: estimateNutritionKey)
    }

    public static let providerKey = "aiProvider"
    public static let anthropicModelKey = "aiAnthropicModel"
    public static let openAIModelKey = "aiOpenAIModel"
    public static let localModelKey = "aiLocalModel"
    public static let localBaseURLKey = "aiLocalBaseURL"
    public static let localVisionKey = "aiLocalVisionCapable"

    /// Free-text and user-editable — providers rename models, so
    /// nothing hardcode-gates on these. Anthropic's default is a
    /// CAPABLE tier, not the cheapest: identify-food and describe-it
    /// are vision/estimation tasks where a small model falls back to
    /// the modal answer ("vegetable stir fry" for any plate it can't
    /// resolve — field report 2026-07-24). Set a cheaper model in
    /// Settings → AI if that trade is worth it for you (or a stronger
    /// one — claude-opus-5 — if Sonnet still under-identifies).
    /// Both defaults are the provider's MID tier — the cheap tiers
    /// (claude-haiku-4-5, and the gpt-4o-mini this replaces) answer an
    /// unresolvable plate with the modal dish instead of admitting it.
    /// gpt-4o-mini was also two generations stale: 4o → 5.4 → 5.6, and
    /// the small tiers were renamed away from mini/nano entirely.
    public static let defaultAnthropicModel = "claude-sonnet-5"
    public static let defaultOpenAIModel = "gpt-5.6-terra"

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

    /// Read by account, mirroring `saveSecret(_:account:)`.
    ///
    /// Settings needs the symmetric reader to answer "has a key changed
    /// since the sheet opened?" — the question its Cancel depends on, and
    /// which it could not ask while only the three named getters existed.
    public static func secret(account: String) -> String {
        readSecret(account) ?? ""
    }

    /// Save (non-empty) or clear (empty). Trimmed like the FDC key.
    @discardableResult
    public static func saveSecret(_ raw: String, account: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            // BOTH groups: a key entered before the move may still have
            // a copy in the old one, and "cleared" has to mean cleared.
            SecItemDelete(query(account) as CFDictionary)
            SecItemDelete(legacyQuery(account) as CFDictionary)
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

    /// The APP GROUP doubles as the keychain access group, which is what
    /// lets the share extension read these at all: keychain items with
    /// no access group land in the app's own, keyed to its bundle id,
    /// and an extension has a different one. An app-group identifier is
    /// valid here without a team prefix — the
    /// `com.apple.security.application-groups` entitlement both targets
    /// already carry is what authorises it — so this needs no new
    /// entitlement and no build-time knowledge of the team ID.
    private static func query(_ account: String) -> [String: Any] {
        var q = legacyQuery(account)
        q[kSecAttrAccessGroup as String] = SharedStore.appGroupID
        return q
    }

    /// Where secrets lived before the extension needed them: the app's
    /// default access group.
    private static func legacyQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    /// Read-through migration, the shape `fdcAPIKey` already uses for its
    /// own move: look in the shared group, and on a miss look where the
    /// key USED to live, copy it across, and delete the original. A key
    /// entered before this change keeps working without being re-typed
    /// — silently re-entering credentials is the failure this avoids.
    /// Test seam: the real accounts are the provider keys, and a test
    /// must not touch those.
    public static func readSecretForTesting(_ account: String) -> String? {
        readSecret(account)
    }

    private static func readSecret(_ account: String) -> String? {
        if let found = read(query(account)) { return found }
        guard let legacy = read(legacyQuery(account)) else { return nil }
        // The legacy copy is deliberately LEFT IN PLACE. Deleting it
        // took the key with it: a keychain query that omits
        // kSecAttrAccessGroup matches every group the app can reach, so
        // `SecItemDelete(legacyQuery)` deleted the copy just written to
        // the shared group as well — and an Anthropic key vanished,
        // reading in Settings as "not set up" (2026-08-16). A duplicate
        // in the app's own group is harmless: reads prefer the shared
        // one, and clearing a secret already deletes from both.
        _ = saveSecret(legacy, account: account)
        return legacy
    }

    private static func read(_ base: [String: Any]) -> String? {
        var q = base
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
