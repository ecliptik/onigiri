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
        case all, meals, foods
    }

    var pending: Action?

    /// One-shot request for TodayView to present the quick-log sheet,
    /// pre-filtered. An Optional rather than a Bool so an unconsumed request
    /// survives until a view is ready — re-setting a stuck `true` flag never
    /// fires onChange again, which left quick actions dead on device.
    var quickLogRequest: QuickLogKind?
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
