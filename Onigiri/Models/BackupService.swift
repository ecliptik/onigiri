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
        // Nothing to protect ⇒ nothing to write. A fresh install's
        // first-launch auto-backup used to snapshot the EMPTY library —
        // and, with date-only filenames, overwrite a real same-day
        // backup that was about to be restored (2026-07-16). Not
        // stamping lastBackupKey here means the first real content
        // still gets backed up promptly.
        let hasContent = ((try? context.fetchCount(FetchDescriptor<Food>())) ?? 0) > 0
            || ((try? context.fetchCount(FetchDescriptor<Meal>())) ?? 0) > 0
            || ((try? context.fetchCount(FetchDescriptor<GoalSettings>())) ?? 0) > 0
        guard hasContent else { return nil }
        guard let directory = backupsDirectory,
              let data = try? LibraryTransfer.export(from: context) else { return nil }

        // Date AND time: two backups can never claim the same name, so
        // a write can never destroy an earlier file (the second half of
        // the 2026-07-16 lesson). Fixed-locale, filename-safe.
        let url = directory.appendingPathComponent("onigiri-backup-\(Self.stampFormatter.string(from: now)).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        SharedStore.defaults.set(now, forKey: lastBackupKey)
        prune(in: directory)
        return url
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    /// The newest backup on disk, by modification date (covers legacy
    /// day-stamped names and the timestamped ones alike).
    static func latestBackup() -> URL? {
        guard let directory = backupsDirectory else { return nil }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("onigiri-backup-") }
            .max { modified($0) < modified($1) }
    }

    /// Keep only the newest `keepCount` backups — by modification date,
    /// which orders legacy day-stamped and timestamped names correctly
    /// in one corpus (lexicographic name sort doesn't).
    private static func prune(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
        }
        let backups = files
            .filter { $0.lastPathComponent.hasPrefix("onigiri-backup-") }
            .sorted { modified($0) > modified($1) }
        for stale in backups.dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
