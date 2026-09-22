import SwiftUI
import Testing
@testable import OnigiriKit

/// The theme setting's resolve rules: absent/garbage reads as System, and
/// only System declines to override the color scheme.
struct AppThemeTests {
    @Test func absentOrUnknownResolvesToSystem() {
        #expect(AppTheme.resolve(nil) == .system)
        #expect(AppTheme.resolve("") == .system)
        // A value written by some future build must not brick the app's
        // appearance — it reads as "follow iOS", like an absent key.
        #expect(AppTheme.resolve("sepia") == .system)
    }

    @Test func explicitChoicesRoundTrip() {
        #expect(AppTheme.resolve("light") == .light)
        #expect(AppTheme.resolve("dark") == .dark)
        #expect(AppTheme.resolve("system") == .system)
    }

    @Test func onlySystemDeclinesToOverride() {
        #expect(AppTheme.system.colorScheme == nil)
        #expect(AppTheme.light.colorScheme == .light)
        #expect(AppTheme.dark.colorScheme == .dark)
    }

    @Test func everyCaseHasALabelAndTheSystemDefaultLeads() {
        #expect(AppTheme.allCases.first == .system)
        #expect(AppTheme.allCases.map(\.label) == ["System", "Light", "Dark"])
    }
}
