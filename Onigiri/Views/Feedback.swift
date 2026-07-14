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
        // an announcement it (and its Undo) is sighted-only.
        UIAccessibility.post(notification: .announcement, argument: message)
        Task {
            // Undoable toasts linger so the button is actually reachable.
            try? await Task.sleep(for: .seconds(undo == nil ? 2 : 5))
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
            .animation(.snappy, value: center.current?.id)
    }
}

/// The one way food and water get logged or removed from the phone UI:
/// HealthKit write + widget reload + haptic + toast with Undo. Every
/// surface calling this behaves identically.
@MainActor
enum LogActions {
    @discardableResult
    static func logFood(
        name: String,
        kcal: Double,
        sodiumMg: Double,
        nutrients: NutrientValues = NutrientValues(),
        category: FoodCategory,
        date: Date = .now
    ) async -> Bool {
        do {
            let id = try await HealthKitService().logFood(
                name: name, kcal: kcal, sodiumMg: sodiumMg,
                nutrients: nutrients, category: category, date: date
            )
            didMutate(haptic: .success)
            ToastCenter.shared.show("Logged \(name) ✓") {
                Task {
                    try? await HealthKitService().deleteFoodEntry(id: id)
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
            let id = try await HealthKitService().logWater(oz: oz, date: date)
            didMutate(haptic: .success)
            let amount = oz.formatted(.number.precision(.fractionLength(0)))
            ToastCenter.shared.show("Logged \(amount) oz water ✓") {
                Task {
                    try? await HealthKitService().deleteWaterEntry(id: id)
                    didMutate(haptic: nil)
                }
            }
        } catch {
            ToastCenter.shared.show("Couldn't log water: \(error.localizedDescription)")
        }
    }

    /// Rescale a logged entry (the log row's Edit): replace it with the
    /// same food at `quantity` servings of what was logged, at `date`
    /// (nil keeps the original time — passing one moves the entry, the
    /// "logged at 11 pm but it was yesterday's dinner" fix). Undo
    /// restores the original entry.
    static func editFoodEntry(
        _ entry: FoodLogEntry, quantity: Double, category: FoodCategory, date: Date? = nil
    ) async {
        do {
            // Replacement is written before the original is deleted (and
            // undo restores before it deletes): a failed write can then
            // never lose the entry, only leave both — and the rollback
            // below covers the delete-failed case.
            let newId = try await HealthKitService().logFood(
                name: entry.name,
                kcal: entry.kcal * quantity,
                sodiumMg: entry.sodiumMg * quantity,
                nutrients: entry.nutrients.scaled(by: quantity),
                category: category,
                date: date ?? entry.date
            )
            do {
                try await HealthKitService().deleteFoodEntry(id: entry.id)
            } catch {
                try? await HealthKitService().deleteFoodEntry(id: newId)
                throw error
            }
            didMutate(haptic: .success)
            ToastCenter.shared.show("Updated \(entry.name) ✓") {
                Task {
                    do {
                        try await HealthKitService().logFood(
                            name: entry.name, kcal: entry.kcal, sodiumMg: entry.sodiumMg,
                            nutrients: entry.nutrients, category: entry.category,
                            date: entry.date
                        )
                        try? await HealthKitService().deleteFoodEntry(id: newId)
                        didMutate(haptic: nil)
                    } catch {
                        ToastCenter.shared.show("Couldn't undo: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            ToastCenter.shared.show("Couldn't update: \(error.localizedDescription)")
        }
    }

    /// Removes a log entry immediately — no confirmation alert. The Undo
    /// toast re-logs the captured values, so an accidental swipe costs
    /// one tap (the old alert claimed "can't be undone", which was
    /// false, and made delete a four-gesture trip).
    static func deleteFoodEntry(_ entry: FoodLogEntry) async {
        do {
            try await HealthKitService().deleteFoodEntry(id: entry.id)
            didMutate(haptic: nil)
            ToastCenter.shared.show("Removed \(entry.name) ✓") {
                Task {
                    do {
                        try await HealthKitService().logFood(
                            name: entry.name, kcal: entry.kcal, sodiumMg: entry.sodiumMg,
                            nutrients: entry.nutrients, category: entry.category,
                            date: entry.date
                        )
                        didMutate(haptic: nil)
                    } catch {
                        ToastCenter.shared.show("Couldn't undo: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            ToastCenter.shared.show("Couldn't delete: \(error.localizedDescription)")
        }
    }

    static func deleteWaterEntry(_ entry: WaterLogEntry) async {
        do {
            try await HealthKitService().deleteWaterEntry(id: entry.id)
            didMutate(haptic: nil)
            let amount = entry.oz.formatted(.number.precision(.fractionLength(0)))
            ToastCenter.shared.show("Removed \(amount) oz ✓") {
                Task {
                    do {
                        try await HealthKitService().logWater(oz: entry.oz, date: entry.date)
                        didMutate(haptic: nil)
                    } catch {
                        ToastCenter.shared.show("Couldn't undo: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            ToastCenter.shared.show("Couldn't delete: \(error.localizedDescription)")
        }
    }

    /// Replace a water entry with a new amount and/or time, same
    /// write-then-delete ordering and undo shape as the food edit.
    static func editWaterEntry(_ entry: WaterLogEntry, oz: Double, date: Date) async {
        do {
            let newId = try await HealthKitService().logWater(oz: oz, date: date)
            do {
                try await HealthKitService().deleteWaterEntry(id: entry.id)
            } catch {
                try? await HealthKitService().deleteWaterEntry(id: newId)
                throw error
            }
            didMutate(haptic: .success)
            ToastCenter.shared.show("Updated water ✓") {
                Task {
                    do {
                        try await HealthKitService().logWater(oz: entry.oz, date: entry.date)
                        try? await HealthKitService().deleteWaterEntry(id: newId)
                        didMutate(haptic: nil)
                    } catch {
                        ToastCenter.shared.show("Couldn't undo: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            ToastCenter.shared.show("Couldn't update: \(error.localizedDescription)")
        }
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
