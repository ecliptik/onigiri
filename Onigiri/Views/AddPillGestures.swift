import SwiftUI
import UIKit

/// Window-level gestures for the corner "+" pill (the system search-role
/// Tab, which exposes no SwiftUI hooks of its own).
///
/// TAP: intercepts the touch BEFORE the tab-bar button fires and routes to
/// the add flow directly. This is the "+"-flash fix: letting the tab
/// activate makes SwiftUI cross-fade the whole content area to the `.log`
/// tab's empty content (~10 frames of white wash-out, frame-captured
/// 2026-07-18) even though the bounce reverts it. Canceling the touch at
/// recognition means the selection never changes, so there is nothing to
/// animate. The `.onChange` bounce in ContentView stays as the fallback for
/// activations that don't arrive as touches (VoiceOver, keyboard) or that
/// slip past the hit test.
///
/// LONG-PRESS: logs one water serving — the fastest water path now that
/// the capsule is gone and water lives inside the Log sheet.
///
/// Device hardening (the first long-press cut worked under XCUITest but
/// not on hardware): recognizers install on EVERY window of the scene
/// (system chrome can host the pill outside the key window), recognize
/// simultaneously with system gestures (a tab bar's own recognizers must
/// not starve ours), and the hit test falls back to the pill's FRAME when
/// the touched view's own accessibility chain doesn't carry the "Add"
/// label. Hold-release today does NOT activate the tab — proof that
/// `cancelsTouchesInView` beats the tab button on hardware; the tap
/// recognizer rides the same mechanism.
struct AddPillGestures: UIViewRepresentable {
    let onTap: () -> Void
    let onLongPress: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onLongPress: onLongPress)
    }

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
        private let onTap: () -> Void
        private let onLongPress: () -> Void
        private var recognizers: [UIGestureRecognizer] = []

        init(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
            self.onTap = onTap
            self.onLongPress = onLongPress
        }

        func installIfNeeded(from view: UIView) {
            guard recognizers.isEmpty, let scene = view.window?.windowScene else { return }
            for window in scene.windows {
                let press = UILongPressGestureRecognizer(target: self, action: #selector(pressFired))
                press.minimumPressDuration = 0.45
                press.cancelsTouchesInView = true
                press.delegate = self
                window.addGestureRecognizer(press)
                recognizers.append(press)

                let tap = UITapGestureRecognizer(target: self, action: #selector(tapFired))
                // Recognition cancels the pill's own touch delivery, so the
                // tab-bar button never fires and the selection never moves.
                tap.cancelsTouchesInView = true
                tap.delegate = self
                window.addGestureRecognizer(tap)
                recognizers.append(tap)
            }
        }

        func removeAll() {
            for recognizer in recognizers {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizers = []
        }

        /// Simultaneous with SYSTEM recognizers (a tab bar's own must not
        /// starve ours) but EXCLUSIVE within our own tap/long-press pair:
        /// a tap has no maximum duration, so after a hold recognized and
        /// logged water, the release would ALSO recognize as a tap and
        /// open the add flow (caught by testAddPillLongPressLogsWater).
        /// Exclusive means first-to-recognize prevents the other.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            !recognizers.contains(other)
        }

        /// The reverse dependency: any NON-OURS recognizer on a pill touch
        /// waits for ours to resolve, so a recognizer-driven tab activation
        /// can't race our tap. Never applied between our own pair — a tap
        /// recognizer has no max duration, so it hasn't "failed" while the
        /// finger is still down and the long-press would deadlock waiting.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            !recognizers.contains(other)
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
            // compact width only — the SIZE CLASS, not a 500pt guess:
            // Split View/Stage Manager windows cross any fixed width
            // while the trait tracks where the tab bar actually is.
            guard window.isKeyWindow,
                  window.rootViewController?.presentedViewController == nil,
                  window.traitCollection.horizontalSizeClass == .compact else { return false }
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

        @objc private func pressFired(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            onLongPress()
        }

        @objc private func tapFired(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            onTap()
        }
    }
}
