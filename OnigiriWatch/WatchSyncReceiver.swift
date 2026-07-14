import Foundation
import WatchConnectivity
import OnigiriKit

/// Receives the library + settings pushed from the iPhone and persists them
/// in the shared defaults where the complications can also read them.
@Observable
final class WatchSyncReceiver: NSObject, WCSessionDelegate {
    private(set) var meals: [SyncedMeal] = WatchSync.loadMeals()
    private(set) var recentFoods: [SyncedMeal] = WatchSync.loadRecentFoods()
    private(set) var favorites: [SyncedMeal] = WatchSync.loadFavorites()
    private(set) var goal: SyncedGoal? = WatchSync.loadGoal()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Background-wake entry (`.backgroundTask(.watchConnectivity)`):
    /// applies whatever context is queued before the caller returns —
    /// the delegate path hops queues, and the process re-suspends the
    /// moment the background task completes, stranding a merely
    /// scheduled apply.
    @MainActor
    func receiveQueuedContext() async {
        guard WCSession.isSupported() else { return }
        activate()
        // Near-instant when already activated; brief poll otherwise so
        // receivedApplicationContext is populated before we read it.
        for _ in 0..<20 where WCSession.default.activationState != .activated {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let context = WCSession.default.receivedApplicationContext
        guard !context.isEmpty else { return }
        apply(WatchSync.parse(context))
        // apply()'s complication reload is debounced — flush it now,
        // the suspension won't wait for the debounce window.
        WidgetReloader.flushNow()
    }

    @MainActor
    private func apply(_ payload: SyncPayload) {
        // The phone pushes on every foreground; most contexts change
        // nothing a complication renders (or nothing at all). Reload the
        // complication timelines — each a full HealthKit fan-out — only
        // when a complication-relevant value actually changed.
        let before = Self.complicationFingerprint()
        WatchSync.store(payload)
        // nil/.keep mean the data was missing or undecodable (version
        // skew) — hold on to the last good copy.
        if let meals = payload.meals {
            self.meals = meals
        }
        if let recents = payload.recentFoods {
            self.recentFoods = recents
        }
        if let favorites = payload.favorites {
            self.favorites = favorites
        }
        switch payload.goal {
        case .set(let goal): self.goal = goal
        case .clear: self.goal = nil
        case .keep: break
        }
        if Self.complicationFingerprint() != before {
            WidgetReloader.requestReload(kinds: WidgetKinds.watchAll)
        }
    }

    /// Everything the complications render out of the synced context: the
    /// goal, the water goal, the calorie-display style, the badge emoji,
    /// the tracked-metric slots, and the sodium limit. Meal/food lists
    /// deliberately excluded — no complication shows them.
    @MainActor
    private static func complicationFingerprint() -> Int {
        let defaults = SharedStore.defaults
        var hasher = Hasher()
        hasher.combine(WatchSync.loadGoal())
        hasher.combine(SharedStore.waterGoalOz)
        hasher.combine(defaults.string(forKey: SharedStore.balanceStyleKey))
        hasher.combine(defaults.string(forKey: SharedStore.rewardIconKey))
        hasher.combine(SharedStore.sodiumLimitMg)
        for key in WatchSync.trackedMetricKeys {
            if WatchSync.trackedNumericKeys.contains(key) {
                hasher.combine(defaults.double(forKey: key))
            } else {
                hasher.combine(defaults.string(forKey: key))
            }
        }
        return hasher.finalize()
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
