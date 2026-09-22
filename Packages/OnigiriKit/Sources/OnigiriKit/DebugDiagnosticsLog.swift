import Foundation

#if DEBUG
/// A durable, pullable record of the budget's inputs — on EITHER device.
///
/// **`print()` does not reach an agent shell, and a device console cannot
/// answer this question anyway** (2026-09-20). `devicectl device process
/// launch --console` streams over a pipe, so Swift's stdout is
/// block-buffered; a handful of short lines never fill the buffer, and
/// the process is signalled rather than exiting, so nothing is ever
/// flushed. Two launches — phone and watch — produced zero app output
/// while both apps ran fine. Same wall `viDebugLog` and the menu
/// parser's `debugScanned`/`scanNote` already hit (CLAUDE.md), so the
/// same fix: write it where `devicectl device copy from --domain-type
/// appDataContainer` can reach it.
///
/// It APPENDS, and that is the point rather than a detail. A phone/watch
/// budget disagreement has to be captured while it is live — the
/// HealthKit window is up to about an hour and `TodayBurnFloor`'s mark
/// only rises within a calendar day — and a console you must already be
/// attached to at that moment cannot do that. Open the app when you
/// notice the gap; pull the file whenever.
///
///     xcrun devicectl device copy from --device <id> \
///       --domain-type appDataContainer \
///       --domain-identifier <bundle id> \
///       --source Documents/budget-diagnostics.log \
///       --destination <local path>
///
/// `Documents`, not the App Group: the group container is shared with
/// the widgets, and `copy from` addresses an app's own data container.
public enum DebugDiagnosticsLog {
    public static let fileName = "budget-diagnostics.log"

    /// Uncapped, a long debugging session grows this without bound — the
    /// cap `viDebugLog` and `WidgetBurnGate`'s journals already carry,
    /// for the reason they carry it.
    private static let cap = 400

    /// One stamped block per launch. Failures are swallowed: a
    /// diagnostic that can take the app down with it is worse than no
    /// diagnostic.
    public static func append(_ lines: [String], now: Date = .now) {
        guard !lines.isEmpty else { return }
        let url = URL.documentsDirectory.appendingPathComponent(fileName)
        var existing = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init) ?? []
        let stamp = now.formatted(
            Date.VerbatimFormatStyle(
                format: """
                    \(month: .twoDigits)-\(day: .twoDigits) \
                    \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\
                    \(minute: .twoDigits):\(second: .twoDigits)
                    """,
                timeZone: .current,
                calendar: .current
            )
        )
        existing.append(contentsOf: lines.map { "[\(stamp)] \($0)" })
        if existing.count > cap { existing.removeFirst(existing.count - cap) }
        try? (existing.joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
