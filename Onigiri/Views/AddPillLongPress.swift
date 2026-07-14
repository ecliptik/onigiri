import SwiftUI
import UIKit

/// Long-pressing the corner "+" pill logs one water serving — the fastest
/// water path now that the capsule is gone and water lives inside the Log
/// sheet. The pill is the system search-role Tab, which exposes no
/// SwiftUI long-press hook, so window-level recognizers stand in. Device
/// hardening (the first cut worked under XCUITest but not on hardware):
/// recognizers install on EVERY window of the scene (system chrome can
/// host the pill outside the key window), recognize simultaneously with
/// system gestures (a tab bar's own recognizers must not starve ours),
/// and the hit test falls back to the pill's FRAME when the touched
/// view's own accessibility chain doesn't carry the "Add" label.
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
        coordinator.removeAll()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let onLongPress: () -> Void
        private var recognizers: [UILongPressGestureRecognizer] = []

        init(onLongPress: @escaping () -> Void) {
            self.onLongPress = onLongPress
        }

        func installIfNeeded(from view: UIView) {
            guard recognizers.isEmpty, let scene = view.window?.windowScene else { return }
            for window in scene.windows {
                let press = UILongPressGestureRecognizer(target: self, action: #selector(fired))
                press.minimumPressDuration = 0.45
                press.cancelsTouchesInView = true
                press.delegate = self
                window.addGestureRecognizer(press)
                recognizers.append(press)
            }
        }

        func removeAll() {
            for recognizer in recognizers {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizers = []
        }

        /// The tab bar's own recognizers must not force ours to wait for
        /// their failure.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// Touches that didn't start on the pill never reach the
        /// recognizer, so every other gesture in the app is untouched.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            // Cheap path: the touched view (or an ancestor) carries the
            // Tab's title as its accessibility label.
            var view: UIView? = touch.view
            while let current = view {
                if current.accessibilityLabel == "Add" { return true }
                view = current.superview
            }
            // Device path: accessibility often lives on non-view
            // elements — find the pill view anywhere in this window and
            // test the touch point against its frame.
            guard let window = gestureRecognizer.view as? UIWindow else { return false }
            if let pill = Self.findAddPill(in: window) {
                let frame = pill.convert(pill.bounds, to: window)
                return frame.insetBy(dx: -8, dy: -8).contains(touch.location(in: window))
            }
            // Last resort (device 2026-07-13: neither strategy above
            // found the pill — SwiftUI's tab bar keeps labels on
            // accessibility elements, not views): the pill is the
            // floating circle at the bottom-trailing corner, so match
            // the region itself. Key window only, nothing presented
            // (a sheet's own bottom corner must not log water), and
            // compact widths only (iPad tab bars live elsewhere).
            guard window.isKeyWindow,
                  window.rootViewController?.presentedViewController == nil,
                  window.bounds.width < 500 else { return false }
            let point = touch.location(in: window)
            return point.x >= window.bounds.width - 84
                && point.y >= window.bounds.height - 130
        }

        static func findAddPill(in view: UIView) -> UIView? {
            if view.accessibilityLabel == "Add" || view.accessibilityIdentifier == "Add" {
                return view
            }
            for sub in view.subviews.reversed() {
                if let found = findAddPill(in: sub) { return found }
            }
            return nil
        }

        @objc private func fired(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            onLongPress()
        }
    }
}
