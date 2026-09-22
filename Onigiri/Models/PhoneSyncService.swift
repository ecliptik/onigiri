import Foundation
import OSLog
import SwiftData
import UIKit
import WatchConnectivity
import OnigiriKit

/// One background-task assertion, ended exactly once.
///
/// For work a background WAKE starts that has no completion handler of
/// its own to hold the process open. Ending it is idempotent, because
/// both the normal path and iOS's expiry callback have to be able to —
/// and an assertion left open past expiry is a termination, not a
/// warning.
@MainActor
private final class BackgroundAssertion {
    private var token: UIBackgroundTaskIdentifier = .invalid

    init(_ name: String) {
        token = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard token != .invalid else { return }
        UIApplication.shared.endBackgroundTask(token)
        token = .invalid
    }
}

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
    /// See `WatchSyncFingerprintCache` — the pure state and the
    /// watch-reinstall invalidation rule this class relies on both live
    /// there now, tested in isolation from WatchConnectivity/UIKit
    /// (health-check audit, 2026-08-31).
    @MainActor private var fingerprints = WatchSyncFingerprintCache()

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
        // the watch pages show the first ten of each list. `recencyDate`
        // is `lastUsedAt ?? createdAt`, so the sort itself touches no
        // relationship; the mapping below is what does.
        var mealFetch = FetchDescriptor<Meal>()
        // Every figure taken off a meal here — totalKcal, totalSodiumMg,
        // totalNutrients, loggedItems — reduces over `items`, so without
        // prefetching, each meal pays its own round trip to fault that
        // relationship in. This runs on every foreground and every
        // debounced log, over the WHOLE library (the 10-row caps below
        // apply to the payload, not to this walk).
        mealFetch.relationshipKeyPathsForPrefetching = [\.items]
        let allMeals = ((try? context.fetch(mealFetch)) ?? [])
            .sorted { $0.recencyDate > $1.recencyDate }
        // Fetched BEFORE the mapping below, and that ordering is load
        // bearing: `MealItem.kcal` reads through to its food, and these
        // rows are registered in the context by the time it does. Moving
        // this after the map restores the second level of the same N+1,
        // which no prefetch keypath can express — `\Meal.items.food`
        // isn't sayable, `items` being an array.
        let allFoods = ((try? context.fetch(FetchDescriptor<Food>())) ?? [])
            .sorted { $0.recencyDate > $1.recencyDate }
        // `isMeal` rides every row so the watch can mark meals the way
        // the phone's lists do. Set EXPLICITLY on both sides — a food
        // sending nil would be indistinguishable from an old phone's
        // payload, and the watch renders nil as unmarked.
        let meals = allMeals.map { SyncedMeal(
            id: $0.uuid, name: $0.name, kcal: $0.totalKcal, sodiumMg: $0.totalSodiumMg,
            category: $0.category, nutrients: $0.totalNutrients,
            items: $0.loggedItems, isMeal: true
        ) }
        let recentFoods = allFoods.prefix(10).map { SyncedMeal(
            id: UUID(), name: $0.name, kcal: $0.kcal, sodiumMg: $0.sodiumMg,
            category: $0.category, nutrients: $0.nutrients, isMeal: false
        ) }
        // Favorites mix meals and foods like the phone's Favorites scope,
        // interleaved by recency before the cap. Meal rows REUSE the
        // synced rows built above (zip is index-aligned with allMeals):
        // totalKcal/totalNutrients reduce over `items`, and rebuilding
        // them here walked every favorite meal's items a second time on
        // every push (audit, 2026-08-17).
        let favorites = (
            zip(allMeals, meals).filter { $0.0.isFavorite }
                .map { ($0.0.recencyDate, $0.1) }
            + allFoods.filter(\.isFavorite).map { food in
                (food.recencyDate, SyncedMeal(
                    id: UUID(), name: food.name, kcal: food.kcal, sodiumMg: food.sodiumMg,
                    category: food.category, nutrients: food.nutrients, isMeal: false
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

        let balanceStyle = SharedStore.defaults.string(forKey: SharedStore.balanceStyleKey) ?? "remaining"
        let foodIcon = SharedStore.defaults.string(forKey: SharedStore.foodIconKey) ?? "sfFork"
        let waterIcon = SharedStore.defaults.string(forKey: SharedStore.waterIconKey) ?? "sfDrop"
        let rewardIcon = SharedStore.defaults.string(forKey: SharedStore.rewardIconKey) ?? "onigiri"
        let mealIcon = SharedStore.defaults.string(forKey: SharedStore.mealIconKey) ?? "plate"
        // The tracked-metric slots ride verbatim (targets stringified);
        // the watch's metrics page mirrors the phone's configuration.
        // Unit preferences ride the same dict, always sent ("auto" when
        // unset) — see WatchSync.unitPreferenceKeys for why.
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
            + WatchSync.unitPreferenceKeys.map { key in
                (key, SharedStore.defaults.string(forKey: key) ?? SharedStore.unitAutomatic)
            }
            // And the plan preferences, already resolved — see
            // WatchSync.planPreferencePairs for why the weight basis has
            // to reach the watch at all.
            + WatchSync.planPreferencePairs
        )
        // The phone's plan weight rides along: the watch's Health store
        // purges old samples, so one older than that window is invisible
        // there and the two devices' plans drift. A cached read — this
        // path must stay synchronous for flushNow. The day STAMP is a
        // day key, but under the 7-day basis the VALUE also shifts when a
        // daily low crosses the trailing cutoff, so the send-skip
        // fingerprint moves once or twice a day rather than once per
        // weigh-in. Cheap: planWeight is deliberately outside
        // settingsFingerprint, so none of that reloads a widget.
        // The trailing-average burn that used
        // to travel beside it went with the average-based budget
        // (2026-08-02): both devices read the day's own Health channels
        // now, and those already agree.
        //
        // It must be the BASIS weight, never the raw weigh-in. The watch
        // prefers whatever arrives here over its own read, so sending the
        // latest sample put its deficit on a different weight than the
        // phone's from the day v2.19.0 shipped — the one thing
        // `targetBasisWeightLb` exists to prevent.
        let planWeight = HealthKitService.cachedPlanWeightLb()
        // The last observed Health log write: its change is what wakes
        // the watch complications (HealthKit's own sync carries the
        // sample, but watchOS caps its background delivery at hourly).
        let lastLogAt = WatchSync.lastPhoneLogAt()?.timeIntervalSince1970
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
            mealIcon: mealIcon,
            trackedMetricSettings: trackedSettings,
            sodiumLimitMg: SharedStore.sodiumLimitMg,
            planWeightLb: planWeight?.lb,
            planWeightDay: planWeight?.day,
            lastLogAt: lastLogAt
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
        settingsHasher.combine(mirrorPayload.mealIcon)
        settingsHasher.combine(mirrorPayload.trackedMetricSettings)
        settingsHasher.combine(mirrorPayload.sodiumLimitMg)
        // planWeight/lastLogAt deliberately excluded: the phone's
        // widgets never read them (they're the watch's inputs), and their
        // daily day-stamp turnover would fire a full reloadAll for nothing.
        let settingsFingerprint = settingsHasher.finalize()
        if !fingerprints.mirrorUnchanged(from: mirrorFingerprint) {
            fingerprints.recordMirrored(mirrorFingerprint)
            WatchSync.store(mirrorPayload)
            // Siri's parameterized phrases ("Log <meal> in Onigiri")
            // speak the mirror just written — refresh their vocabulary
            // so a renamed or new meal/food is sayable without waiting
            // for the system's periodic sweep.
            OnigiriShortcuts.updateAppShortcutParameters()
            // Widgets render from the mirror just written — every goal,
            // settings, and library change lands here, so this is the one
            // place a reload keeps them from going up to ~30 min stale.
            if !fingerprints.settingsUnchanged(from: settingsFingerprint) {
                WidgetReloader.requestReloadAll()
            } else {
                // Library-only (every log bumps recency and lands here):
                // scoped, like the HealthKit observer's reload — the
                // full reload was recomputing the trend chart per log.
                WidgetReloader.requestReload(kinds: WidgetKinds.phoneLogAffected)
            }
        }
        fingerprints.recordSettings(settingsFingerprint)

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
        guard !fingerprints.sentUnchanged(from: sendFingerprint) else { return }
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
                mealIcon: mealIcon,
                trackedMetricSettings: trackedSettings,
                sodiumLimitMg: SharedStore.sodiumLimitMg,
                planWeightLb: planWeight?.lb,
                planWeightDay: planWeight?.day,
                lastLogAt: lastLogAt
            ))
            fingerprints.recordSent(sendFingerprint)
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
            // Forget what was last SENT: this process may be talking to a
            // watch that no longer holds it (see sessionWatchStateDidChange).
            self.fingerprints.invalidateSent()
            self.onActivate?()
        }
    }

    /// The watch was paired, unpaired, or — the case that bit — had the
    /// app REINSTALLED. A reinstall wipes the watch's library, but the
    /// sent fingerprint still holds what the OLD installation was sent,
    /// so the next push computes an identical fingerprint and SKIPS the
    /// send. The watch then sits on "add favorites or log food in the
    /// app" forever while the phone's library is full, and only a phone
    /// relaunch (which cleared this in-memory state) or an unrelated
    /// library edit broke the deadlock (field report 2026-07-30). See
    /// `WatchSyncFingerprintCache.invalidateSent` for the regression test
    /// this exact bug now has.
    ///
    /// Clearing the fingerprint and re-pushing costs one application
    /// context update — the cheapest possible push — and only when the
    /// watch's install/pair state actually moves.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.fingerprints.invalidateSent()
            self.onActivate?()
        }
    }

    /// A log happened ON THE WATCH.
    ///
    /// The only inbound WatchConnectivity traffic. HealthKit carries the
    /// sample itself, but watchOS caps its background delivery at roughly
    /// hourly, so this arrives first — and reminders bake their text at
    /// planning time, which is how a 7 AM watch-logged glass of water
    /// left the 11 AM check-in insisting nothing had been logged (the
    /// user, 2026-08-17; `plans/PLAN-reminders.md`).
    ///
    /// The ARRIVAL is the signal; the timestamp inside only keeps
    /// successive transfers distinct. Health may not have synced the
    /// sample yet when this lands — the replan re-queries and the
    /// foreground replan still backstops it, so an early wake costs one
    /// replan and nothing else.
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        guard userInfo[WatchSync.watchLogNoticeKey] != nil else { return }
        Task { @MainActor in
            Self.log.notice("watch log notice — replanning reminders")
            // This is usually a BACKGROUND wake, and unlike HKObserverQuery
            // — which gates on an explicit completion handler — this
            // delegate method has nothing to hold the process open with:
            // it returns the instant the Task above is created. Without an
            // assertion the replan can be suspended away, which is the very
            // gap this channel exists to close.
            let assertion = BackgroundAssertion("watch-log-replan")
            defer { assertion.end() }
            WidgetReloader.requestReload(kinds: WidgetKinds.phoneLogAffected)
            // Awaited, not fired-and-forgotten: this may be a background
            // wake, and the process re-suspends once the delegate's work
            // settles — a merely-scheduled replan would be stranded.
            await ReminderScheduler.shared.replanNow(afterMutation: true)
            WidgetReloader.flushNow()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
