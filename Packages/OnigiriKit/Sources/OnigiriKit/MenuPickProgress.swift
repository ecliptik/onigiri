import Foundation

/// What a list you are still choosing from says about what you have
/// already taken off it (`plans/PLAN-multi-item-import.md`).
///
/// One read, several items: a nutrition guide is read once and ordered
/// from several times. The note is the whole confirmation — the picker
/// never leaves, so a toast that appears over it and a note that stays
/// in it are not interchangeable, and this is the one that is still
/// there when you look up from the menu.
///
/// Pure and here rather than in either host, because the app and the
/// share extension both show it and a sentence that drifts between two
/// processes is a sentence nobody can test.
public enum MenuPickProgress {
    /// `nil` before anything is logged — there is nothing to report and
    /// an empty footer is not a message.
    ///
    /// Names the LAST item in both forms. After four picks the count is
    /// what answers "how far am I", and the name is what answers "did
    /// that one take" — neither alone does both.
    public static func note(logged: [String]) -> String? {
        guard let last = logged.last else { return nil }
        return logged.count == 1
            ? "Logged \(last). Choose another, or tap Done."
            : "Logged \(logged.count) items, last \(last). Choose another, or tap Done."
    }
}
