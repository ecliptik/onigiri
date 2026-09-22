import SwiftUI

/// The appearance the iOS app forces on itself (Settings → Appearance →
/// Theme). Absent or unknown = `.system`, so every install that predates
/// the setting keeps following iOS exactly as before.
///
/// Deliberately narrow in scope, and the wiki says so:
/// - **Widgets cannot follow it.** WidgetKit renders its entries in the
///   SYSTEM appearance; a `preferredColorScheme` set on the app's window
///   has no reach into the extension's process. This key is not part of
///   the widget contract and must not be treated as one.
/// - **The watch ignores it** — watchOS has no light appearance. The key
///   deliberately does NOT ride the watch sync (only the three unit keys
///   must, because an absent key there would leave a stale explicit
///   choice alive).
/// - **The launch screen follows the system**, so Light-under-a-dark-system
///   shows one dark frame before the window applies the override.
public enum AppTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// What SwiftUI's `.preferredColorScheme` wants: nil means "don't
    /// override — follow iOS".
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The UIKit override lives in the iOS app (`AppearanceWindow`), not
    /// here: this type is shared with the watch, which has no `UIWindow`.

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Absent, empty, or a value from a newer build all read as `.system`
    /// — the same forgiving resolve the unit preferences use.
    public static func resolve(_ raw: String?) -> AppTheme {
        raw.flatMap(AppTheme.init(rawValue:)) ?? .system
    }
}

public extension SharedStore {
    /// Raw theme setting; absent = follow the system.
    static let appearanceKey = "appearance"

    static var appTheme: AppTheme {
        AppTheme.resolve(defaults.string(forKey: appearanceKey))
    }
}
