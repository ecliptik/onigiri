import Foundation

/// Where a picked dish came from, folded into its name
/// (`plans/PLAN-menu-import.md`).
///
/// "Egg White Grill (Chik Fil A)", matching how the library already
/// reads — "Margarita (Cayman Jack)". The source TRAILS the dish in
/// brackets rather than leading it behind a dash (the user, 2026-08-16):
/// the dish is what you scan the list for, so it goes first.
///
/// Pure and here rather than in the picker, because the answer can now
/// arrive AFTER the item has been chosen — a single shared item confirms
/// itself while the prompt is still up — so the rule is applied more
/// than once against the same dish and has to be idempotent. That is the
/// property a view cannot state and a test can.
public enum MenuSourceName {
    /// The name to log. Trims both sides, refuses to bracket nothing,
    /// and never appends a suffix the name already carries.
    public static func applied(to name: String, source: String) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return name }
        // A nameless read still knows where it came from, and "(CAVA)"
        // alone is not a name.
        guard !name.isEmpty else { return source }
        let suffix = "(\(source))"
        guard !name.hasSuffix(suffix, caseInsensitive: true) else { return name }
        return "\(name) \(suffix)"
    }
}

private extension String {
    /// Case-insensitive because the answer is typed by hand, and
    /// "greek chicken (cava)" must not earn a second "(CAVA)".
    func hasSuffix(_ suffix: String, caseInsensitive: Bool) -> Bool {
        guard caseInsensitive else { return hasSuffix(suffix) }
        guard count >= suffix.count else { return false }
        return self.suffix(suffix.count).caseInsensitiveCompare(suffix) == .orderedSame
    }
}
