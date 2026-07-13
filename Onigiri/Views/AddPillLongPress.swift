import SwiftUI
import UIKit

/// Long-pressing the corner "+" pill logs one water serving — the fastest
/// water path now that the capsule is gone and water lives inside the Log
/// sheet. The pill is the system search-role Tab, which exposes no
/// SwiftUI long-press hook, so a window-level recognizer stands in: it
/// receives ONLY touches that land on the pill (accessibility label
/// "Add", the Tab's title) and cancels them when it fires, which keeps
/// the tab switch — and its Log-sheet bounce — from also running on
/// release.
struct AddPillLongPress: UIViewRepresentable {
    let onLongPress: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLongPress: onLongPress) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        // The window isn't reachable until the view lands in it.
        DispatchQueue.main.async { context.coordinator.installIfNeeded(from: view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { context.coordinator.installIfNeeded(from: uiView) }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let onLongPress: () -> Void
        private var recognizer: UILongPressGestureRecognizer?
        private weak var window: UIWindow?

        init(onLongPress: @escaping () -> Void) {
            self.onLongPress = onLongPress
        }

        func installIfNeeded(from view: UIView) {
            guard recognizer == nil, let window = view.window else { return }
            let press = UILongPressGestureRecognizer(target: self, action: #selector(fired))
            press.minimumPressDuration = 0.45
            press.cancelsTouchesInView = true
            press.delegate = self
            window.addGestureRecognizer(press)
            recognizer = press
            self.window = window
        }

        func remove() {
            if let recognizer, let window {
                window.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
        }

        /// Touches that didn't start on the pill never reach the
        /// recognizer, so every other gesture in the app is untouched.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            var view: UIView? = touch.view
            while let current = view {
                if current.accessibilityLabel == "Add" { return true }
                view = current.superview
            }
            return false
        }

        @objc private func fired(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            onLongPress()
        }
    }
}
