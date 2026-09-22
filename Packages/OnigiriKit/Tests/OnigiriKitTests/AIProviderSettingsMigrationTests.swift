import Testing
import Foundation
@testable import OnigiriKit

/// The health-check audit's coverage gap: `AIProviderSettings`'s
/// read-through keychain migration has no regression test, even though
/// it's the actual fix for a documented 2026-08-16 production incident
/// — a user's Anthropic key read as "not set up" after one successful
/// use, because the migration deleted "the legacy copy" with a query
/// that OMITS `kSecAttrAccessGroup` — which (as the source comment
/// explains) matches every access group the app can reach, so that
/// delete took the freshly-migrated shared copy with it too. The fix
/// keeps the legacy copy in place; what this suite actually checks is
/// the observable guarantee that matters — a key found once keeps being
/// found on every later read, migration included.
///
/// (A "does a legacy copy specifically still exist" seam was tried and
/// dropped: the same query-omits-access-group behavior that caused the
/// incident also means such a query can't distinguish a legacy-only
/// item from a migrated one once both exist — it matches either. The
/// repeated-read behavior below is what's actually observable and
/// actually the point.)
///
/// A dedicated fake account, never the real provider accounts.
/// Serialized: keychain items under this account are shared, mutable
/// state across these tests.
@Suite(.serialized)
struct AIProviderSettingsMigrationTests {
    private let account = "__test_migration_account__"

    init() { AIProviderSettings.deleteSecretForTesting(account) }

    @Test func aLegacyOnlyKeyKeepsBeingFoundAfterMigrating() {
        AIProviderSettings.writeLegacySecretForTesting("sk-legacy-key", account: account)
        defer { AIProviderSettings.deleteSecretForTesting(account) }

        // The migrating read.
        #expect(AIProviderSettings.readSecretForTesting(account) == "sk-legacy-key")
        // The regression, pinned directly: the OLD migration deleted the
        // key on its own first read, so it vanished on the very NEXT
        // one. Reading it again, twice, is what actually distinguishes
        // "migrated and preserved" from "migrated and silently lost".
        #expect(AIProviderSettings.readSecretForTesting(account) == "sk-legacy-key")
        #expect(AIProviderSettings.readSecretForTesting(account) == "sk-legacy-key")
    }

    @Test func noKeyAnywhereReadsAsNil() {
        #expect(AIProviderSettings.readSecretForTesting(account) == nil)
    }

    @Test func aKeyAlreadyInTheSharedLocationNeedsNoMigrationAndKeepsReading() {
        AIProviderSettings.saveSecret("sk-current-key", account: account)
        defer { AIProviderSettings.deleteSecretForTesting(account) }
        #expect(AIProviderSettings.readSecretForTesting(account) == "sk-current-key")
        #expect(AIProviderSettings.readSecretForTesting(account) == "sk-current-key")
    }

    /// Clearing is documented to reach BOTH locations, unlike the
    /// migration's deliberately-legacy-preserving read — pinned so a
    /// future change to either can't quietly swap one behavior for the
    /// other and leave a "cleared" key still answering from Settings.
    @Test func clearingASecretActuallyRemovesIt() {
        AIProviderSettings.writeLegacySecretForTesting("sk-legacy-key", account: account)
        AIProviderSettings.saveSecret("sk-current-key", account: account)
        #expect(AIProviderSettings.readSecretForTesting(account) != nil)

        AIProviderSettings.saveSecret("", account: account)

        #expect(AIProviderSettings.readSecretForTesting(account) == nil, "clearing must remove every copy, legacy included")
    }
}
