import Foundation

/// What the app calls the food energy you have taken in.
///
/// It had four names for one quantity — "Intake" on Today's meter,
/// "eaten" on Today's budget card, "logged" on Details, and briefly
/// "consumed" on Goal (the user, 2026-08-13). Rather than pick one and
/// impose it, the word is a preference; this type is the only place any
/// surface may get it from.
///
/// The three are NOT grammatically interchangeable, which is why this
/// exposes a noun and not a raw string: "1,100 of 2,000 kcal eaten"
/// reads fine and "…kcal intake" does not. Every site uses `label` in a
/// noun slot, so no sentence can break when the setting changes.
public enum IntakeWord: String, CaseIterable, Sendable {
    // Raw values are STORED preferences: never rename them.
    case eaten, intake, consumed

    /// Absent/unrecognized reads as the default the app shipped with.
    public static func resolve(_ raw: String?) -> IntakeWord {
        raw.flatMap(IntakeWord.init(rawValue:)) ?? .eaten
    }

    /// Sentence-case noun, for a row label or the head of a caption:
    /// "Eaten", "Intake", "Consumed".
    public var label: String {
        switch self {
        case .eaten: "Eaten"
        case .intake: "Intake"
        case .consumed: "Consumed"
        }
    }

    /// Lower-case noun, for mid-sentence use.
    public var lowercased: String { label.lowercased() }
}

public extension SharedStore {
    /// The chosen word. Absent = "eaten".
    static let intakeWordKey = "intakeWord"
    static var intakeWord: IntakeWord {
        IntakeWord.resolve(defaults.string(forKey: intakeWordKey))
    }
}
