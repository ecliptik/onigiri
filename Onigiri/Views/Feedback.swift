import SwiftUI
import OnigiriKit

/// One toast for the whole app, hosted at the root so every surface —
/// tabs, sheets that dismiss on log, undo taps — reports the same way.
@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()

    struct Item: Identifiable {
        let id = UUID()
        let message: String
        let undo: (@MainActor () -> Void)?
    }

    private(set) var current: Item?
    /// Bumped on every log/delete/undo so open screens can refresh.
    private(set) var mutationVersion = 0
    /// Bumped whenever the HealthKit observer reports a log change —
    /// including writes this app never saw (widget intent buttons, the
    /// watch, third-party apps). The foreground staleness gates compare
    /// against it so an external write always forces a refresh.
    private(set) var healthWriteVersion = 0

    func show(_ message: String, undo: (@MainActor () -> Void)? = nil) {
        let item = Item(message: message, undo: undo)
        current = item
        // The toast is the app's primary confirmation channel — without
        // an announcement it (and its Undo) is sighted-only. Deletes
        // have no confirmation alert, so the announcement must SAY an
        // Undo exists or VoiceOver users never learn about the only
        // recovery path.
        UIAccessibility.post(
            notification: .announcement,
            argument: undo == nil ? message : "\(message), Undo available"
        )
        Task {
            // Undoable toasts linger so the button is actually reachable —
            // and much longer under VoiceOver, where "reachable" means
            // locating a transient overlay by touch.
            let linger: Double = if undo == nil { 2 }
                else if UIAccessibility.isVoiceOverRunning { 15 }
                else { 5 }
            try? await Task.sleep(for: .seconds(linger))
            if current?.id == item.id { current = nil }
        }
    }

    func noteMutation() {
        mutationVersion += 1
    }

    func noteHealthWrite() {
        healthWriteVersion += 1
    }

    fileprivate func performUndo(_ item: Item) {
        current = nil
        item.undo?()
    }
}

extension View {
    /// Attach once at the app root.
    func toastHost() -> some View {
        modifier(ToastHost())
    }
}

/// Liquid Glass on iOS 26, frosted material below — same capsule, same
/// copy, the OS's own idiom either way (PLAN-1.8's floor rule).
private struct ToastChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: .capsule)
        }
    }
}

private struct ToastHost: ViewModifier {
    @State private var center = ToastCenter.shared
    /// Reduce Motion: the toast appears/disappears in place instead of
    /// sliding up from the bottom edge.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let item = center.current {
                    HStack(spacing: 12) {
                        // Body-size text with roomier padding — the
                        // subheadline capsule read too small against the
                        // rest of the app (the user).
                        Text(item.message)
                            .font(.body.weight(.medium))
                        if item.undo != nil {
                            Button("Undo") {
                                center.performUndo(item)
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.riceToast)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .modifier(ToastChrome())
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: center.current?.id)
    }
}

/// The one way food and water get logged or removed from the phone UI:
/// HealthKit write + widget reload + haptic + toast with Undo. Every
/// surface calling this behaves identically.
@MainActor
enum LogActions {
    /// ONE service for every log/undo: a fresh instance per call owned a
    /// fresh HKHealthStore and an empty correlation cache, so every undo
    /// took the by-UUID re-query fallback the cache exists to avoid.
    private static let health = HealthKitService()

    @discardableResult
    static func logFood(
        name: String,
        kcal: Double,
        sodiumMg: Double,
        nutrients: NutrientValues = NutrientValues(),
        category: FoodCategory,
        date: Date = .now,
        aiGenerated: Bool = false,
        quantity: Double = 1
    ) async -> Bool {
        do {
            let id = try await health.logFood(
                name: name, kcal: kcal, sodiumMg: sodiumMg,
                nutrients: nutrients, category: category, date: date,
                aiGenerated: aiGenerated, quantity: quantity
            )
            didMutate(haptic: .success)
            ToastCenter.shared.show("Logged \(name) ✓") {
                Task {
                    try? await health.deleteFoodEntry(id: id)
                    didMutate(haptic: nil)
                }
            }
            return true
        } catch {
            ToastCenter.shared.show("Couldn't log: \(error.localizedDescription)")
            return false
        }
    }

    static func logWater(oz: Double, date: Date = .now) async {
        do {
            let id = try await health.logWater(oz: oz, date: date)
            didMutate(haptic: .success)
            ToastCenter.shared.show("Logged \(SharedStore.waterUnit.text(fromOz: oz)) water ✓") {
                Task {
                    try? await health.deleteWaterEntry(id: id)
                    didMutate(haptic: nil)
                }
            }
        } catch {
            ToastCenter.shared.show("Couldn't log water: \(error.localizedDescription)")
        }
    }

    /// Rescale a logged entry (the log row's Edit): replace it with the
    /// same food at `quantity` portions — on the entry's PER-PORTION
    /// basis (its totals ÷ its stored quantity), so 3 logged hot dogs
    /// edited to 2 means two hot dogs, not two triple-portions — at
    /// `date` (nil keeps the original time — passing one moves the
    /// entry, the "logged at 11 pm but it was yesterday's dinner" fix).
    /// Undo restores the original entry.
    static func editFoodEntry(
        _ entry: FoodLogEntry, quantity: Double, category: FoodCategory, date: Date? = nil
    ) async {
        do {
            // Replacement is written before the original is deleted (and
            // undo restores before it deletes): a failed write can then
            // never lose the entry, only leave both — and the rollback
            // below covers the delete-failed case.
            let scale = quantity / entry.quantity
            let newId = try await health.logFood(
                name: entry.name,
                kcal: entry.kcal * scale,
                sodiumMg: entry.sodiumMg * scale,
                nutrients: entry.nutrients.scaled(by: scale),
                category: category,
                date: date ?? entry.date,
                aiGenerated: entry.aiGenerated,
                quantity: quantity
            )
            do {
                try await health.deleteFoodEntry(id: entry.id)
            } catch {
                try? await health.deleteFoodEntry(id: newId)
                throw error
            }
            didMutate(haptic: .success)
            ToastCenter.shared.show("Updated \(entry.name) ✓") {
                Task {
                    do {
                        try await health.logFood(
                            name: entry.name, kcal: entry.kcal, sodiumMg: entry.sodiumMg,
                            nutrients: entry.nutrients, category: entry.category,
                            date: entry.date, aiGenerated: entry.aiGenerated,
                            quantity: entry.quantity
                        )
                        try? await health.deleteFoodEntry(id: newId)
                        didMutate(haptic: nil)
                    } catch {
                        ToastCenter.shared.show("Couldn't undo: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            ToastCenter.shared.show(failureMessage(error, verb: "update"))
        }
    }

    /// Removes a log entry immediately — no confirmation alert. The Undo
    /// toast re-logs the captured values, so an accidental swipe costs
    /// one tap (the old alert claimed "can't be undone", which was
    /// false, and made delete a four-gesture trip).
    static func deleteFoodEntry(_ entry: FoodLogEntry) async {
        do {
            try await health.deleteFoodEntry(id: entry.id)
            didMutate(haptic: nil)
            ToastCenter.shared.show("Removed \(entry.name) ✓") {
                Task {
                    do {
                        try await health.logFood(
                            name: entry.name, kcal: entry.kcal, sodiumMg: entry.sodiumMg,
                            nutrients: entry.nutrients, category: entry.category,
                            date: entry.date, aiGenerated: entry.aiGenerated,
                            quantity: entry.quantity
                        )
                        didMutate(haptic: nil)
                    } catch {
                        ToastCenter.shared.show("Couldn't undo: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            ToastCenter.shared.show(failureMessage(error, verb: "delete"))
        }
    }

    static func deleteWaterEntry(_ entry: WaterLogEntry) async {
        do {
            try await health.deleteWaterEntry(id: entry.id)
            didMutate(haptic: nil)
            ToastCenter.shared.show("Removed \(SharedStore.waterUnit.text(fromOz: entry.oz)) ✓") {
                Task {
                    do {
                        try await health.logWater(oz: entry.oz, date: entry.date)
                        didMutate(haptic: nil)
                    } catch {
                        ToastCenter.shared.show("Couldn't undo: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            ToastCenter.shared.show(failureMessage(error, verb: "delete"))
        }
    }

    /// Replace a water entry with a new amount and/or time, same
    /// write-then-delete ordering and undo shape as the food edit.
    static func editWaterEntry(_ entry: WaterLogEntry, oz: Double, date: Date) async {
        do {
            let newId = try await health.logWater(oz: oz, date: date)
            do {
                try await health.deleteWaterEntry(id: entry.id)
            } catch {
                try? await health.deleteWaterEntry(id: newId)
                throw error
            }
            didMutate(haptic: .success)
            ToastCenter.shared.show("Updated water ✓") {
                Task {
                    do {
                        try await health.logWater(oz: entry.oz, date: entry.date)
                        try? await health.deleteWaterEntry(id: newId)
                        didMutate(haptic: nil)
                    } catch {
                        ToastCenter.shared.show("Couldn't undo: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            ToastCenter.shared.show(failureMessage(error, verb: "update"))
        }
    }

    /// Delete/edit failures on entries another app saved come back as
    /// authorization errors — blaming Health access sends the user to
    /// Settings for nothing. Name the actual fix.
    private static func failureMessage(_ error: Error, verb: String) -> String {
        HealthKitService.isForeignObjectError(error)
            ? "Another app logged this entry — remove it in the Health app."
            : "Couldn't \(verb): \(error.localizedDescription)"
    }

    private static func didMutate(haptic: UINotificationFeedbackGenerator.FeedbackType?) {
        // No widget reload here: the HealthKit observer (ContentView) fires
        // for this same write and reloads through the debounced funnel — a
        // direct reload just doubled every log's widget storm.
        if let haptic {
            UINotificationFeedbackGenerator().notificationOccurred(haptic)
        }
        ToastCenter.shared.noteMutation()
        // A log can satisfy (or revive) pending reminders — replan.
        ReminderScheduler.shared.replan(afterMutation: true)
    }
}
