import Testing
import Foundation
@testable import OnigiriKit

/// `SharedStore.quarantineCorruptStore` — the step between a store that
/// won't open at all and a fatalError crash loop with no recovery
/// (health-check audit, 2026-09-14). Pure file-system logic, tested
/// without a real ModelContainer.
struct StoreRecoveryTests {
    private func tempStoreURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Onigiri.sqlite")
    }

    @Test func movesTheMainFileAndBothSidecars() throws {
        let url = try tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        for ext in ["", "-wal", "-shm"] {
            try Data("x".utf8).write(to: URL(fileURLWithPath: url.path + ext))
        }

        let moved = SharedStore.quarantineCorruptStore(at: url, suffix: "test")
        #expect(moved)
        for ext in ["", "-wal", "-shm"] {
            #expect(!FileManager.default.fileExists(atPath: url.path + ext), "original \(ext.isEmpty ? "store" : ext) file must be gone")
            #expect(FileManager.default.fileExists(atPath: url.path + ext + ".corrupt-test"), "quarantined \(ext) copy must exist")
        }
    }

    @Test func movesOnlyWhicheverSidecarsActuallyExist() throws {
        let url = try tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // Only the main file — no -wal/-shm, a perfectly normal state
        // for a store that's been checkpointed and closed cleanly.
        try Data("x".utf8).write(to: url)

        let moved = SharedStore.quarantineCorruptStore(at: url, suffix: "test")
        #expect(moved)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: url.path + ".corrupt-test"))
    }

    @Test func nothingToQuarantineReportsFalse() throws {
        let url = try tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // No files at all — the directory exists but the store never did.
        #expect(!SharedStore.quarantineCorruptStore(at: url, suffix: "test"))
    }

    /// The quarantined file must survive — this whole mechanism exists
    /// so a corrupt store is recoverable by hand later, not gone.
    @Test func quarantinedContentIsPreservedExactly() throws {
        let url = try tempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("the original bytes".utf8).write(to: url)

        #expect(SharedStore.quarantineCorruptStore(at: url, suffix: "test"))
        let preserved = try Data(contentsOf: URL(fileURLWithPath: url.path + ".corrupt-test"))
        #expect(String(data: preserved, encoding: .utf8) == "the original bytes")
    }
}
