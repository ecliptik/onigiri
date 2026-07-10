import SwiftUI
import WidgetKit
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

    func show(_ message: String, undo: (@MainActor () -> Void)? = nil) {
        let item = Item(message: message, undo: undo)
        current = item
        Task {
            // Undoable toasts linger so the button is actually reachable.
            try? await Task.sleep(for: .seconds(undo == nil ? 2 : 5))
            if current?.id == item.id { current = nil }
        }
    }

    func noteMutation() {
        mutationVersion += 1
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

private struct ToastHost: ViewModifier {
    @State private var center = ToastCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let item = center.current {
                    HStack(spacing: 12) {
                        Text(item.message)
                            .font(.subheadline.weight(.medium))
                        if item.undo != nil {
                            Button("Undo") {
                                center.performUndo(item)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.riceToast)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
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

    /// Removes a log entry; Undo re-logs the same values at the same time
    /// (trans fat is the one detail HealthKit can't give back).
    static func deleteFoodEntry(_ entry: FoodLogEntry) async {
        do {
            try await HealthKitService().deleteFoodEntry(id: entry.id)
            didMutate(haptic: nil)
            ToastCenter.shared.show("Removed \(entry.name) ✓") {
                Task {
                    try? await HealthKitService().logFood(
                        name: entry.name, kcal: entry.kcal, sodiumMg: entry.sodiumMg,
                        nutrients: entry.nutrients, category: entry.category,
                        date: entry.date
                    )
                    didMutate(haptic: nil)
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
                    try? await HealthKitService().logWater(oz: entry.oz, date: entry.date)
                    didMutate(haptic: nil)
                }
            }
        } catch {
            ToastCenter.shared.show("Couldn't delete: \(error.localizedDescription)")
        }
    }

    private static func didMutate(haptic: UINotificationFeedbackGenerator.FeedbackType?) {
        WidgetCenter.shared.reloadAllTimelines()
        if let haptic {
            UINotificationFeedbackGenerator().notificationOccurred(haptic)
        }
        ToastCenter.shared.noteMutation()
    }
}
