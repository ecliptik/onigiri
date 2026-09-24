import XCTest
@testable import Onigiri

/// The two fixed-format date strings the app writes and reads — the
/// backup file name and the Today deep link's `day` — moved off
/// `DateFormatter` onto `FormatStyle` (2026-09-24,
/// `plans/PLAN-audit-salvage.md`). A format swap can change a string
/// silently, and backup names are what the user sees in Files, so each
/// is checked against the formatter it replaced as well as by literal.
final class DateStampFormatTests: XCTestCase {
    /// Exactly what `BackupService` used before.
    private let legacyStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    /// Exactly what `ContentView.deepLinkDay` was before.
    private let legacyDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: .current, year: y, month: mo, day: d,
                                 hour: h, minute: mi, second: s))!
    }

    func testBackupStampLiterals() {
        // Single-digit month, day, hour, minute and second: every field pads.
        XCTAssertEqual(BackupService.stampFormat.format(local(2026, 9, 4, 7, 5, 9)), "2026-09-04-070509")
        // Midnight is 00, not 24 or 12.
        XCTAssertEqual(BackupService.stampFormat.format(local(2026, 1, 1, 0, 0, 0)), "2026-01-01-000000")
        XCTAssertEqual(BackupService.stampFormat.format(local(2026, 12, 31, 23, 59, 59)), "2026-12-31-235959")
    }

    func testBackupStampMatchesTheFormatterItReplaced() {
        // Every hour of a year, at an odd minute/second, plus a leap day.
        var dates = [local(2028, 2, 29, 13, 4, 5)]
        var date = local(2026, 1, 1, 0, 7, 3)
        let end = local(2027, 1, 1)
        while date < end {
            dates.append(date)
            date = date.addingTimeInterval(3_600 * 7 + 61)
        }
        for date in dates {
            XCTAssertEqual(BackupService.stampFormat.format(date), legacyStamp.string(from: date))
        }
    }

    func testDeepLinkDayParsesToLocalMidnight() throws {
        let parsed = try Date("2026-09-04", strategy: ContentView.deepLinkDay)
        XCTAssertEqual(parsed, local(2026, 9, 4))
    }

    func testDeepLinkDayMatchesTheFormatterItReplaced() {
        let inputs = [
            "2026-09-04", "2026-01-01", "2026-12-31", "2028-02-29",
            // Rejected by both: a strict parse refuses these rather than
            // rolling them into some other day.
            "2026-02-30", "2027-02-29", "2026-13-01", "2026-00-10",
            "", "garbage", "2026-09", "20260904",
        ]
        for input in inputs {
            XCTAssertEqual(
                try? Date(input, strategy: ContentView.deepLinkDay),
                legacyDay.date(from: input),
                "\"\(input)\" parses differently from the old formatter"
            )
        }
    }

    /// The ONE deliberate difference, found by the test above: ICU let
    /// the old formatter read any separator, so "2026/09/04" parsed as
    /// the 4th. The format says hyphens, and nothing sends a `day` yet,
    /// so the stricter reading stands — pinned so it stays a decision.
    func testDeepLinkDayRefusesAnotherSeparator() {
        XCTAssertNotNil(legacyDay.date(from: "2026/09/04"))
        XCTAssertNil(try? Date("2026/09/04", strategy: ContentView.deepLinkDay))
    }
}
