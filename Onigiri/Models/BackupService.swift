import Foundation
import SwiftData
import OnigiriKit

/// Silent safety net for the library: writes the JSON export into the app's
/// Documents folder (visible in the Files app, included in the phone's
/// iCloud device backup) at most once a day, keeping the last five.
/// The hand-entered library is the one thing HealthKit doesn't hold.
enum BackupService {
    static let lastBackupKey = "backup.lastDate"
    private static let keepCount = 5

    static var backupsDirectory: URL? {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return nil }
        let directory = documents.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var lastBackupDate: Date? {
        SharedStore.defaults.object(forKey: lastBackupKey) as? Date
    }

    /// Writes a backup if the last one is over a day old (or `force`d).
    /// Returns the file URL when a backup was written. Synchronous on
    /// purpose: a detached write raced the launch path's double call and
    /// could be suspended with the process before the file landed — the
    /// few-ms encode of a personal library isn't worth either failure.
    @discardableResult
    @MainActor
    static func backupIfDue(context: ModelContext, force: Bool = false, now: Date = .now) -> URL? {
        if !force, let last = lastBackupDate,
           now.timeIntervalSince(last) < 24 * 3600 {
            return nil
        }
        guard let directory = backupsDirectory,
              let data = try? LibraryTransfer.export(from: context) else { return nil }

        let stamp = now.formatted(.iso8601.year().month().day())
        let url = directory.appendingPathComponent("onigiri-backup-\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        SharedStore.defaults.set(now, forKey: lastBackupKey)
        prune(in: directory)
        return url
    }

    /// Keep only the newest `keepCount` backups.
    private static func prune(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let backups = files
            .filter { $0.lastPathComponent.hasPrefix("onigiri-backup-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for stale in backups.dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
