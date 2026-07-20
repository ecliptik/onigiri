import SwiftUI
import Testing
@testable import OnigiriKit

/// The status twins — VoiceOver label, Differentiate Without Color
/// symbol — must classify exactly like the color they shadow: one
/// drifted threshold and a surface lies to precisely the users the
/// twin exists for.
struct BrandColorsStatusTests {
    @Test func sodiumTwinsAgreeAtTheThresholds() {
        // Under (limit − 300 is the near edge) → both twins silent.
        #expect(Color.sodiumStatusLabel(mg: 1999, limitMg: 2300) == nil)
        #expect(Color.sodiumStatusSymbol(mg: 1999, limitMg: 2300) == nil)
        // Near: within 300 mg of the limit, inclusive of the limit.
        #expect(Color.sodiumStatusLabel(mg: 2000, limitMg: 2300) == "near limit")
        #expect(Color.sodiumStatusSymbol(mg: 2000, limitMg: 2300) == "exclamationmark.triangle")
        #expect(Color.sodiumStatusLabel(mg: 2300, limitMg: 2300) == "near limit")
        #expect(Color.sodiumStatusSymbol(mg: 2300, limitMg: 2300) == "exclamationmark.triangle")
        // Over: outline becomes filled.
        #expect(Color.sodiumStatusLabel(mg: 2301, limitMg: 2300) == "over limit")
        #expect(Color.sodiumStatusSymbol(mg: 2301, limitMg: 2300) == "exclamationmark.triangle.fill")
    }

    @Test func remainingTwinsAgreeAtTheThresholds() {
        // Comfortably under budget (more than a 150 kcal snack left).
        #expect(Color.remainingStatusLabel(kcal: 151) == nil)
        #expect(Color.remainingStatusSymbol(kcal: 151) == nil)
        // Near: a snack or less left, down to exactly zero.
        #expect(Color.remainingStatusLabel(kcal: 150) == "near budget")
        #expect(Color.remainingStatusSymbol(kcal: 150) == "exclamationmark.triangle")
        #expect(Color.remainingStatusLabel(kcal: 0) == "near budget")
        #expect(Color.remainingStatusSymbol(kcal: 0) == "exclamationmark.triangle")
        // Over: outline becomes filled.
        #expect(Color.remainingStatusLabel(kcal: -1) == "over budget")
        #expect(Color.remainingStatusSymbol(kcal: -1) == "exclamationmark.triangle.fill")
    }
}
