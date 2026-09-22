import XCTest
import OnigiriKit
@testable import Onigiri

/// Can a secret be SAVED and READ BACK? Sounds too basic to test, and it
/// is exactly what broke: after the keychain access-group change an
/// Anthropic key silently failed to store, so "Test connection" stayed
/// greyed out with a key visibly in the field (2026-08-16).
///
/// No class-level @MainActor — the target's `nonisolated` default
/// exists precisely so XCTestCase subclasses don't re-isolate their
/// inherited ObjC init/tearDown (project.yml's own comment); everything
/// here calls nonisolated kit code (audit, 2026-08-17).
final class SecretStorageTests: XCTestCase {
    private let account = "unitTestSecret"

    override func tearDown() {
        AIProviderSettings.saveSecret("", account: account)
        super.tearDown()
    }

    func testASavedSecretReadsBack() throws {
        AIProviderSettings.saveSecret("", account: account)
        let saved = AIProviderSettings.saveSecret("sk-ant-test-value", account: account)
        print("SAVE returned \(saved)")
        let read = AIProviderSettings.readSecretForTesting(account)
        print("READ got \(read ?? "nil")")
        XCTAssertTrue(saved, "SecItemAdd/Update rejected the write")
        XCTAssertEqual(read, "sk-ant-test-value")
    }

    func testClearingRemovesIt() {
        _ = AIProviderSettings.saveSecret("temporary", account: account)
        _ = AIProviderSettings.saveSecret("", account: account)
        XCTAssertNil(AIProviderSettings.readSecretForTesting(account))
    }
}
