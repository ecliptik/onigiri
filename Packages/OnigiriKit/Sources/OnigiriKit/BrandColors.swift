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

    /// The nori green off the app icon's seaweed wrap — the brand's
    /// SECOND accent, for structure (section headers, chrome glyphs):
    /// riceToast stays the interactive tint, greys stay body text.
    /// Deep in light mode; lifted in dark so it reads on black.
    #if canImport(UIKit) && !os(watchOS)
    static let nori = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.66, blue: 0.55, alpha: 1)
            : UIColor(red: 0.20, green: 0.30, blue: 0.21, alpha: 1)
    })
    #else
    static let nori = Color(red: 0.55, green: 0.66, blue: 0.55)
    #endif

    /// The page canvas behind every grouped screen: a warm rice-paper
    /// wash in light mode — the neutral system gray read as any-app
    /// generic once the one-surface idiom landed (the user wanted the
    /// onigiri personality back) — and the system grouped black in
    /// dark, where riceToast already pops. Cards stay white/system on
    /// top of it, so contrast and readability don't move.
    #if canImport(UIKit) && !os(watchOS)
    static let riceCanvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemGroupedBackground
            : UIColor(red: 0.99, green: 0.96, blue: 0.92, alpha: 1)
    })
    #else
    static let riceCanvas = Color(red: 0.99, green: 0.96, blue: 0.92)
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

    /// The non-color twin of `remainingStatus`, colocated so the
    /// thresholds can't drift (the sodiumStatusLabel discipline): the
    /// amber "near budget" warning is otherwise purely visual on every
    /// surface that shows the headline. nil while comfortably under.
    static func remainingStatusLabel(kcal: Double) -> String? {
        if kcal < 0 { return "over budget" }
        if kcal <= 150 { return "near budget" }
        return nil
    }
}
