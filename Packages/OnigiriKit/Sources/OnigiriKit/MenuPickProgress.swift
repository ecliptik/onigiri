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
    /// A row can be taken off the list by being logged to Health, or by
    /// being saved to the library alone — "not necessarily log it" (the
    /// user, 2026-08-29). Both count as progress; only the verb differs.
    public enum Kind: Equatable {
        case logged
        case saved
    }

    public struct Entry: Equatable {
        public let name: String
        public let kind: Kind

        public init(name: String, kind: Kind) {
            self.name = name
            self.kind = kind
        }

        public static func logged(_ name: String) -> Entry { Entry(name: name, kind: .logged) }
        public static func saved(_ name: String) -> Entry { Entry(name: name, kind: .saved) }
    }

    /// `nil` before anything has gone in — there is nothing to report and
    /// an empty footer is not a message.
    ///
    /// Names the LAST item in both forms. After four picks the count is
    /// what answers "how far am I", and the name is what answers "did
    /// that one take" — neither alone does both.
    ///
    /// The VERB follows the LAST entry's kind — "Logged" or "Saved" —
    /// because that is the action the reader just took and the one worth
    /// confirming. The count that follows counts every row taken off the
    /// list so far, logged or saved alike, since both mean "done with
    /// this row." A per-kind tally ("2 logged, 1 saved") was tried and
    /// read as a receipt nobody asked for; which rows were which is the
    /// picker's own marks (checkmark / bookmark) to say, not this line.
    public static func note(_ entries: [Entry]) -> String? {
        guard let last = entries.last else { return nil }
        let verb = last.kind == .logged ? "Logged" : "Saved"
        return entries.count == 1
            ? "\(verb) \(last.name). Choose another, or tap Done."
            : "\(verb) \(entries.count) items, last \(last.name). Choose another, or tap Done."
    }
}
