import Foundation
import SwiftUI
import UIKit
import os

private nonisolated(unsafe) let quickActionLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "quickactions")

/// Home-screen quick actions (long-press the app icon), routed from the
/// scene delegate into SwiftUI.
@Observable
final class QuickActions {
    static let shared = QuickActions()

    enum Action: String {
        case logWater = "com.ecliptik.Onigiri.logWater"
        case logMeal = "com.ecliptik.Onigiri.logMeal"
        case logFood = "com.ecliptik.Onigiri.logFood"
        case scanBarcode = "com.ecliptik.Onigiri.scanBarcode"
    }

    enum QuickLogKind {
        /// Scopes the sheet offers (Foods / Meals / Favorites).
        case foods, meals, favorites
        /// Routing kinds, not scopes: .all lands on Foods; .scan lands
        /// on Foods with the barcode scanner already open — known
        /// barcodes take the 1-tap portion path with the browsed-day
        /// logDate (the Foods-tab food form lost both).
        case all, scan
    }

    var pending: Action?

    /// One-shot request for TodayView to present the quick-log sheet,
    /// pre-filtered. An Optional rather than a Bool so an unconsumed request
    /// survives until a view is ready — re-setting a stuck `true` flag never
    /// fires onChange again, which left quick actions dead on device.
    var quickLogRequest: QuickLogKind?

    /// One-shot request for TodayView to browse to a specific day
    /// (Calendar's "View day"), same consumable-Optional pattern.
    var dayRequest: Date?

    /// One-shot request for FoodsView to open the add-to-library form:
    /// `.food` → new food, `.meal` → new meal. The chooser that sets this
    /// lives in ContentView (presented synchronously as the + is tapped, so
    /// its backdrop covers the search-tab bounce and it survives it — hosting
    /// it on FoodsView flashed, then got dismissed by the tab change).
    /// Consumable Optional, same pattern: a stuck flag never re-fires onChange.
    enum AddFoodKind { case food, meal }
    var addFoodKind: AddFoodKind?

    /// One-shot request to switch to the Goal tab (tapping Today's Daily
    /// Goal card). Consumable Optional, not a Bool: a stuck `true` never
    /// re-fires onChange.
    var goalRequest: Bool?
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            quickActionLog.info("cold-launch shortcut: \(item.type, privacy: .public)")
            QuickActions.shared.pending = QuickActions.Action(rawValue: item.type)
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        quickActionLog.info("warm shortcut: \(shortcutItem.type, privacy: .public)")
        QuickActions.shared.pending = QuickActions.Action(rawValue: shortcutItem.type)
        completionHandler(true)
    }
}
