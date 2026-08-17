import Testing
import Foundation
@testable import OnigiriKit

struct LibraryDuplicateTests {
    @Test func matchesIgnoringCaseAndWhitespace() {
        #expect(LibraryDuplicate.nameMatches("Protein shake", "protein SHAKE"))
        #expect(LibraryDuplicate.nameMatches("  Protein shake ", "Protein shake"))
    }

    @Test func distinctNamesDoNotMatch() {
        #expect(!LibraryDuplicate.nameMatches("Protein shake", "Protein shake vanilla"))
        #expect(!LibraryDuplicate.nameMatches("Two eggs", "Two eggs & toast"))
        #expect(!LibraryDuplicate.nameMatches("", "Protein shake"))
    }

    /// The two shapes of the rule must never disagree — the whole reason
    /// `key` exists is that the bulk paths (backup import) can't afford
    /// the pairwise sweep, and hand-rolling their own comparison is
    /// exactly what drifted (audit, 2026-08-17).
    @Test func theKeyAndThePredicateAgree() {
        let names = [
            "Protein shake", "protein SHAKE", "  Protein shake ", "PROTEIN SHAKE",
            "Two eggs", "two eggs", " two eggs", "Two eggs & toast", "",
            "  ", "Oats", "oats ", " Oats",
        ]
        for lhs in names {
            for rhs in names {
                #expect(
                    LibraryDuplicate.nameMatches(lhs, rhs)
                        == (LibraryDuplicate.key(lhs) == LibraryDuplicate.key(rhs)),
                    "\"\(lhs)\" vs \"\(rhs)\""
                )
            }
        }
    }

    /// The variants each hand-rolled path used to miss: import lowercased
    /// without trimming, the share extension compared exactly.
    @Test func theKeyFoldsCaseAndTrimsTogether() {
        #expect(LibraryDuplicate.key(" Oats") == LibraryDuplicate.key("Oats"))
        #expect(LibraryDuplicate.key("oats") == LibraryDuplicate.key("Oats"))
        #expect(LibraryDuplicate.key(" oats ") == LibraryDuplicate.key("OATS"))
        #expect(LibraryDuplicate.key("Oat s") != LibraryDuplicate.key("Oats"))
    }
}

struct LibraryImportIdentityTests {
    /// A backup's meal uuid is kept when nothing holds it — that is what
    /// makes configured meal widgets survive a restore.
    @Test func anUnclaimedIdentifierIsPreserved() {
        let exported = UUID()
        #expect(LibraryImport.mealUUID(preferring: exported, claimed: []) == exported)
        #expect(LibraryImport.mealUUID(preferring: exported, claimed: [UUID()]) == exported)
    }

    /// The 2026-08-17 audit case: export "Breakfast", RENAME the live meal
    /// to "Morning Meal" (it keeps its uuid), then restore that backup.
    /// The name guard no longer matches, so a second row is created — and
    /// it used to inherit the identifier the live meal still answers to.
    /// `LogMealIntent` resolves with `first(where:)`, so a configured
    /// widget would log whichever of the two came back first.
    @Test func anIdentifierAlreadyLiveIsNotReissued() {
        let shared = UUID()
        #expect(LibraryImport.mealUUID(preferring: shared, claimed: [shared]) == nil)
    }

    /// Two meals inside ONE backup carrying the same uuid must not both
    /// keep it either — the import accumulates what it has handed out.
    @Test func anIdentifierClaimedEarlierInTheSameImportIsNotReissued() {
        let shared = UUID()
        var claimed: Set<UUID> = []
        let first = LibraryImport.mealUUID(preferring: shared, claimed: claimed)
        #expect(first == shared)
        claimed.insert(first ?? UUID())
        #expect(LibraryImport.mealUUID(preferring: shared, claimed: claimed) == nil)
    }

    @Test func aBackupWithNoIdentifierMintsAFreshOne() {
        #expect(LibraryImport.mealUUID(preferring: nil, claimed: []) == nil)
    }
}
