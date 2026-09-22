import UIKit
import OnigiriKit

/// Forces the chosen Theme on the app's WINDOWS, which is the only way it
/// reaches everything.
///
/// `.preferredColorScheme` on the root view covers just that view tree. A
/// sheet is its own `UIHostingController`, so it keeps the appearance it
/// was presented with — and the Theme picker LIVES in a sheet (Settings is
/// presented from Today). Switching to Dark from inside Settings changed
/// the app behind the sheet and left the sheet itself light; switching back
/// to System didn't move it either (field report 2026-07-29).
///
/// A window's `overrideUserInterfaceStyle` cascades to every view
/// controller presented in that window — sheets, alerts, popovers — so one
/// call fixes all of them, including screens that don't exist yet.
@MainActor
enum AppearanceWindow {
    private static func style(_ theme: AppTheme) -> UIUserInterfaceStyle {
        switch theme {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Applies the stored Theme to every window of every connected scene.
    /// Cheap and idempotent, so it's safe to call on launch, on the
    /// setting's change, and on foreground.
    static func apply(_ theme: AppTheme = SharedStore.appTheme) {
        let style = style(theme)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    /// For a window created after the fact — the PrivacyShield floats its
    /// own, and a shield in the wrong appearance would flash the app
    /// switcher's snapshot in the other look.
    static func apply(to window: UIWindow, theme: AppTheme = SharedStore.appTheme) {
        window.overrideUserInterfaceStyle = style(theme)
    }
}
