import SwiftUI

public extension Color {
    /// The warm cream from the app icon's background — bright accent for
    /// filled controls (pair with dark text). Works on light and dark.
    static let ricePaper = Color(red: 0.96, green: 0.83, blue: 0.62)

    /// Text/icon color on a ricePaper fill. Semantic on purpose: raw
    /// `.black` at the call sites breaks silently if ricePaper ever
    /// adapts to dark mode.
    static let onRicePaper = Color.black

    /// A toasted tan used as the app-wide tint. Adapts to the system
    /// appearance: deeper in light mode for contrast on white, brighter in
    /// dark mode so it doesn't muddy against black.
    #if canImport(UIKit) && !os(watchOS)
    static let riceToast = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.89, green: 0.70, blue: 0.42, alpha: 1)
            : UIColor(red: 0.72, green: 0.51, blue: 0.25, alpha: 1)
    })
    #else
    // watchOS renders on black; use the bright variant.
    static let riceToast = Color(red: 0.89, green: 0.70, blue: 0.42)
    #endif

    /// Traffic-light color for a sodium total against the daily limit:
    /// green when comfortably under, toast yellow within 300 mg, red over.
    static func sodiumStatus(mg: Double, limitMg: Double) -> Color {
        if mg > limitMg { return .red }
        if mg >= limitMg - 300 { return .riceToast }
        return .green
    }

    /// The non-color twin of `sodiumStatus`, colocated so the thresholds
    /// can't drift: color alone can't carry "near limit"/"over limit"
    /// (colorblind users, VoiceOver, and the warning tone sits near AA
    /// limits at small sizes). nil while comfortably under.
    static func sodiumStatusLabel(mg: Double, limitMg: Double) -> String? {
        if mg > limitMg { return "over limit" }
        if mg >= limitMg - 300 { return "near limit" }
        return nil
    }

    /// Traffic-light for the "kcal left" headline, mirroring sodiumStatus:
    /// green with room, toast yellow within a snack (150 kcal) of the
    /// budget, orange once over.
    static func remainingStatus(kcal: Double) -> Color {
        if kcal < 0 { return .orange }
        if kcal <= 150 { return .riceToast }
        return .green
    }
}
