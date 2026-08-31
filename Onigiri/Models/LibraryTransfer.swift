import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import OnigiriKit

/// Thin app-target wrapper around `OnigiriKit.LibraryTransfer`.
///
/// The actual export/merge logic moved into the kit (health-check audit,
/// 2026-08-31) so it can be unit tested — see that type's doc comment.
/// This one keeps the exact same name and call signature every site in
/// the app already uses (`LibraryTransfer.export`, `.importData`,
/// `.handlePickedFile`), plus the two things that genuinely belong here:
/// `handlePickedFile`'s app-target `PhoneSyncService` push, and
/// `LibraryJSONDocument` below (SwiftUI's `fileExporter` plumbing).
enum LibraryTransfer {
    @MainActor
    static func export(from context: ModelContext) throws -> Data {
        try OnigiriKit.LibraryTransfer.export(from: context)
    }

    /// Imports additively: foods and meals whose names already exist are
    /// skipped; the goal and water settings are overwritten when present.
    /// Returns a human-readable summary.
    @MainActor
    static func importData(_ data: Data, into context: ModelContext) throws -> String {
        try OnigiriKit.LibraryTransfer.importData(data, into: context)
    }

    /// Shared fileImporter completion — security-scoped read, import, sync
    /// push — returning the outcome line for whichever surface ran it.
    @MainActor
    static func handlePickedFile(_ result: Result<URL, Error>, context: ModelContext) -> String {
        switch result {
        case .success(let url):
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let message = try importData(data, into: context)
                PhoneSyncService.shared.push(from: context)
                return message
            } catch {
                return "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            return "Import failed: \(error.localizedDescription)"
        }
    }
}

/// Wraps export data for SwiftUI's fileExporter.
struct LibraryJSONDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
