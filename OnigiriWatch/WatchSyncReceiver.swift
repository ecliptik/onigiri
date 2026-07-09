import Foundation
import WatchConnectivity
import WidgetKit
import OnigiriKit

/// Receives the library + settings pushed from the iPhone and persists them
/// in the shared defaults where the complications can also read them.
@Observable
final class WatchSyncReceiver: NSObject, WCSessionDelegate {
    private(set) var meals: [SyncedMeal] = WatchSync.loadMeals()
    private(set) var goal: SyncedGoal? = WatchSync.loadGoal()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    @MainActor
    private func apply(_ payload: SyncPayload) {
        WatchSync.store(payload)
        meals = payload.meals
        goal = payload.goal
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        let payload = WatchSync.parse(context)
        Task { @MainActor in
            self.apply(payload)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let payload = WatchSync.parse(applicationContext)
        Task { @MainActor in
            self.apply(payload)
        }
    }
}
