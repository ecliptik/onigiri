import Foundation
import OSLog
import SwiftData
import WatchConnectivity
import OnigiriKit

/// Pushes the library + settings to the watch as the WatchConnectivity
/// application context (latest-wins; delivered when the watch is reachable).
final class PhoneSyncService: NSObject, WCSessionDelegate {
    static let shared = PhoneSyncService()

    private static let log = Logger(subsystem: "com.ecliptik.Onigiri", category: "sync")

    /// The WATCH context caps meals (the pages show ten, only the meal
    /// picker browses further) to stay well under the application-context
    /// size cap. The local App Group mirror stays uncapped — the widget
    /// meal buttons and Shortcuts resolve meals from it, and a capped
    /// mirror turned older meals into "no longer a saved meal" errors.
    private static let maxSyncedMeals = 30

    private var onActivate: (@MainActor () -> Void)?

    @MainActor private var pendingContext: ModelContext?
    @MainActor private var pushTask: Task<Void, Never>?
    /// Fingerprints of what was last mirrored locally / actually sent to
    /// the watch — repeat pushes with nothing changed (every foreground,
    /// chained Settings onChange handlers) skip the mirror write, widget
    /// reload, and radio. Tracked separately: a send skipped because the
    /// session wasn't ready yet must not suppress the retry.
    @MainActor private var lastMirroredFingerprint: Int?
    /// The goal+settings slice of the mirror fingerprint — library-only
    /// changes (a recency bump on every log) must not reload the weight
    /// trend widget, which reads nothing from the library mirror.
    @MainActor private var lastSettingsFingerprint: Int?
    @MainActor private var lastSentFingerprint: Int?

    func activate(onActivate: @escaping @MainActor () -> Void) {
        guard WCSession.isSupported() else { return }
        self.onActivate = onActivate
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            Task { @MainActor in onActivate() }
        } else {
            session.activate()
        }
    }

    /// Coalesce bursts (Settings steppers, chained onChange handlers, a
    /// foreground push racing a mutation's) into one push a second later.
    @MainActor
    func push(from context: ModelContext) {
        pendingContext = context
        guard pushTask == nil else { return }
        pushTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            pushTask = nil
            if let context = pendingContext {
                pendingContext = nil
                pushNow(from: context)
            }
        }
    }

    /// Run any pending push immediately. Call when the scene leaves the
    /// foreground: a suspended (or terminated) process never runs the
    /// sleeping debounce task, and the change would be silently dropped.
    @MainActor
    func flushNow() {
        pushTask?.cancel()
        pushTask = nil
        if let context = pendingContext {
            pendingContext = nil
            pushNow(from: context)
        }
    }

    /// Snapshot meals, goal, and water settings; mirror them into the App
    /// Group defaults (the widget extension reads that — keeps SwiftData out
    /// of its memory-capped process), and send them to the watch if paired.
    @MainActor
    private func pushNow(from context: ModelContext) {
        // Recency order everywhere, matching the phone Log sheet's sort —
        // the watch pages show the first ten of each list.
        let allMeals = ((try? context.fetch(FetchDescriptor<Meal>())) ?? [])
            .sorted { $0.recencyDate > $1.recencyDate }
        let allFoods = ((try? context.fetch(FetchDescriptor<Food>())) ?? [])
            .sorted { $0.recencyDate > $1.recencyDate }
        let meals = allMeals.map { SyncedMeal(
            id: $0.uuid, name: $0.name, kcal: $0.totalKcal, sodiumMg: $0.totalSodiumMg,
            category: $0.category, nutrients: $0.totalNutrients
        ) }
        let recentFoods = allFoods.prefix(10).map { SyncedMeal(
            id: UUID(), name: $0.name, kcal: $0.kcal, sodiumMg: $0.sodiumMg,
            category: $0.category, nutrients: $0.nutrients
        ) }
        // Favorites mix meals and foods like the phone's Favorites scope,
        // interleaved by recency before the cap.
        let favorites = (
            allMeals.filter(\.isFavorite).map { meal in
                (meal.recencyDate, SyncedMeal(
                    id: meal.uuid, name: meal.name, kcal: meal.totalKcal, sodiumMg: meal.totalSodiumMg,
                    category: meal.category, nutrients: meal.totalNutrients
                ))
            }
            + allFoods.filter(\.isFavorite).map { food in
                (food.recencyDate, SyncedMeal(
                    id: UUID(), name: food.name, kcal: food.kcal, sodiumMg: food.sodiumMg,
                    category: food.category, nutrients: food.nutrients
                ))
            }
        ).sorted { $0.0 > $1.0 }.prefix(10).map(\.1)
        let goal = ((try? context.fetch(FetchDescriptor<GoalSettings>())) ?? []).first
            .map { SyncedGoal(
                targetWeightLb: $0.targetWeightLb,
                targetDate: $0.targetDate,
                fallbackCurrentWeightLb: $0.fallbackCurrentWeightLb,
                mode: $0.mode
            ) }

        let balanceStyle = SharedStore.defaults.string(forKey: SharedStore.balanceStyleKey) ?? "balance"
        let foodIcon = SharedStore.defaults.string(forKey: SharedStore.foodIconKey) ?? "sfFork"
        let waterIcon = SharedStore.defaults.string(forKey: SharedStore.waterIconKey) ?? "sfDrop"
        let rewardIcon = SharedStore.defaults.string(forKey: SharedStore.rewardIconKey) ?? "onigiri"
        // The tracked-metric slots ride verbatim (targets stringified);
        // the watch's metrics page mirrors the phone's configuration.
        let trackedSettings: [String: String] = Dictionary(
            uniqueKeysWithValues: WatchSync.trackedMetricKeys.compactMap { key in
                // Numeric targets always send — a reset to 0 ("use the
                // default") must reach the watch, or its old custom
                // target lives on until the slot's nutrient changes.
                if WatchSync.trackedNumericKeys.contains(key) {
                    return (key, String(SharedStore.defaults.double(forKey: key)))
                }
                return SharedStore.defaults.string(forKey: key).map { (key, $0) }
            }
        )
        // Fingerprint the whole payload (SyncPayload is Hashable, so a
        // future field can't be silently missed): pushes where nothing
        // changed — every foreground, chained Settings onChange handlers —
        // skip the mirror write, the widget reload, and the radio.
        // In-memory fingerprints: the first push per launch always goes
        // through, which doubles as recovery from a failed earlier send.
        let mirrorPayload = SyncPayload(
            meals: meals,
            recentFoods: recentFoods,
            favorites: favorites,
            goal: goal.map(GoalUpdate.set) ?? .clear,
            waterServingOz: SharedStore.waterServingOz,
            waterGoalOz: SharedStore.waterGoalOz,
            balanceStyle: balanceStyle,
            foodIcon: foodIcon,
            waterIcon: waterIcon,
            rewardIcon: rewardIcon,
            trackedMetricSettings: trackedSettings,
            sodiumLimitMg: SharedStore.sodiumLimitMg
        )
        let mirrorFingerprint = mirrorPayload.hashValue
        // The goal+settings slice of the payload (everything but the
        // library lists): when THIS half moved, the trend widget (goal
        // target line) needs a reload too; when only the lists moved,
        // it doesn't.
        var settingsHasher = Hasher()
        settingsHasher.combine(mirrorPayload.goal)
        settingsHasher.combine(mirrorPayload.waterServingOz)
        settingsHasher.combine(mirrorPayload.waterGoalOz)
        settingsHasher.combine(mirrorPayload.balanceStyle)
        settingsHasher.combine(mirrorPayload.foodIcon)
        settingsHasher.combine(mirrorPayload.waterIcon)
        settingsHasher.combine(mirrorPayload.rewardIcon)
        settingsHasher.combine(mirrorPayload.trackedMetricSettings)
        settingsHasher.combine(mirrorPayload.sodiumLimitMg)
        let settingsFingerprint = settingsHasher.finalize()
        if mirrorFingerprint != lastMirroredFingerprint {
            lastMirroredFingerprint = mirrorFingerprint
            WatchSync.store(mirrorPayload)
            // Siri's parameterized phrases ("Log <meal> in Onigiri")
            // speak the mirror just written — refresh their vocabulary
            // so a renamed or new meal/food is sayable without waiting
            // for the system's periodic sweep.
            OnigiriShortcuts.updateAppShortcutParameters()
            // Widgets render from the mirror just written — every goal,
            // settings, and library change lands here, so this is the one
            // place a reload keeps them from going up to ~30 min stale.
            if settingsFingerprint != lastSettingsFingerprint {
                WidgetReloader.requestReloadAll()
            } else {
                // Library-only (every log bumps recency and lands here):
                // scoped, like the HealthKit observer's reload — the
                // full reload was recomputing the trend chart per log.
                WidgetReloader.requestReload(kinds: WidgetKinds.phoneLogAffected)
            }
        }
        lastSettingsFingerprint = settingsFingerprint

        // The send-side fingerprint latches only on a successful send: a
        // push skipped here (session still activating, watch briefly
        // unpaired) must retry when the next push comes around.
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled
        else { return }
        let contextMeals = Array(meals.prefix(Self.maxSyncedMeals))
        var sendHasher = Hasher()
        sendHasher.combine(mirrorPayload)
        sendHasher.combine(contextMeals)
        let sendFingerprint = sendHasher.finalize()
        guard sendFingerprint != lastSentFingerprint else { return }
        do {
            try WCSession.default.updateApplicationContext(WatchSync.makeContext(
                meals: contextMeals,
                recentFoods: recentFoods,
                favorites: favorites,
                goal: goal,
                waterServingOz: SharedStore.waterServingOz,
                waterGoalOz: SharedStore.waterGoalOz,
                balanceStyle: balanceStyle,
                foodIcon: foodIcon,
                waterIcon: waterIcon,
                rewardIcon: rewardIcon,
                trackedMetricSettings: trackedSettings,
                sodiumLimitMg: SharedStore.sodiumLimitMg
            ))
            lastSentFingerprint = sendFingerprint
        } catch {
            // A payload-too-large here means the watch silently stops
            // getting updates — it must at least be visible in the log.
            Self.log.error("updateApplicationContext failed: \(error.localizedDescription)")
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.onActivate?()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
