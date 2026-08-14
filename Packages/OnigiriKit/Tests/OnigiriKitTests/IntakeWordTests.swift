import Foundation
import Testing
@testable import OnigiriKit

/// One quantity, one word — chosen once and read everywhere.
struct IntakeWordTests {
    @Test func absentReadsAsTheShippedDefault() {
        #expect(IntakeWord.resolve(nil) == .eaten)
        #expect(IntakeWord.resolve("") == .eaten)
    }

    /// A stored value written by a future version, or a hand-edited
    /// plist, must not crash or blank the label.
    @Test func anUnknownValueFallsBackRatherThanBreaking() {
        #expect(IntakeWord.resolve("devoured") == .eaten)
    }

    /// Raw values are stored preferences — renaming one silently resets
    /// everybody's choice.
    @Test func rawValuesAreTheStoredContract() {
        #expect(IntakeWord.eaten.rawValue == "eaten")
        #expect(IntakeWord.intake.rawValue == "intake")
        #expect(IntakeWord.consumed.rawValue == "consumed")
    }

    /// Every case must read as a NOUN, because every call site puts it
    /// in a noun slot ("Intake 1,100 of 2,128 kcal"). A participle-only
    /// word would break those sentences for one option and not others —
    /// which is exactly why the raw string isn't used directly.
    @Test func everyCaseHasASentenceCaseNoun() {
        for word in IntakeWord.allCases {
            #expect(word.label.first?.isUppercase == true)
            #expect(word.lowercased == word.label.lowercased())
            #expect(!word.label.contains(" "))
        }
        #expect(IntakeWord.eaten.label == "Eaten")
        #expect(IntakeWord.intake.label == "Intake")
        #expect(IntakeWord.consumed.label == "Consumed")
    }
}
