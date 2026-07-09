import Foundation
import SwiftUI
import UIKit

/// Home-screen quick actions (long-press the app icon), routed from the
/// scene delegate into SwiftUI.
@Observable
final class QuickActions {
    static let shared = QuickActions()

    enum Action: String {
        case logWater = "com.ecliptik.Onigiri.logWater"
        case logMeal = "com.ecliptik.Onigiri.logMeal"
        case scanBarcode = "com.ecliptik.Onigiri.scanBarcode"
    }

    var pending: Action?
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem {
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
        QuickActions.shared.pending = QuickActions.Action(rawValue: shortcutItem.type)
        completionHandler(true)
    }
}
