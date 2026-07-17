import SwiftUI
import OnigiriKit

/// Watch home: the day's headline number, with one-tap water and meal
/// logging. Meals and settings sync from the iPhone.
struct WatchHomeView: View {
    let model: WatchModel
    @State private var showMeals = false
    @Environment(\.scenePhase) private var scenePhase
    // AppStorage so an icon/style sync re-renders immediately (the
    // values land in the shared defaults via WatchSync.store) — a plain
    // SharedStore read here didn't repaint until the next log.
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "sfFork"
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @AppStorage(SharedStore.balanceStyleKey, store: SharedStore.defaults) private var balanceStyle = "remaining"

    var body: some View {
        NavigationStack {
            // ScrollView stays — a bare VStack under a navigation title
            // rendered blank on-device (content laid out off-screen; the
            // crown could briefly scroll it into view). Compact spacing
            // and small controls keep everything on one screen anyway.
            ScrollView {
                VStack(spacing: 6) {
                    headlineNumber

                    // Micheal's scheme: meal = rice-paper cream with
                    // dark content (the phone's prominent-Done recipe —
                    // riceToast tan made the fork unreadable), water =
                    // blue, as it always was.
                    Button {
                        showMeals = true
                    } label: {
                        Label {
                            // "Log", not "Log a meal": the sheet mirrors
                            // the phone's default Log view (favorites +
                            // recent, meals and foods mixed), not meals
                            // alone.
                            Text("Log")
                        } icon: {
                            FoodIconView(raw: foodIcon, tint: Color.onRicePaper)
                        }
                        .font(.headline)
                        .foregroundStyle(Color.onRicePaper)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.ricePaper)

                    Button {
                        Task { await model.logWater() }
                    } label: {
                        Label {
                            // No serving suffix — "(12 oz)" overflowed
                            // the small faces; the flash confirms the
                            // amount on log.
                            Text("Log water")
                        } icon: {
                            // Solid white drop on the blue button —
                            // matching the meal button's monochrome fork.
                            WaterIconView(raw: waterIcon, tint: .white)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    // Success flash / failure hint: the haptic alone made
                    // a failed log look exactly like a working one.
                    if let flash = model.flash {
                        Text(flash)
                            .font(.caption2)
                            .foregroundStyle(model.flashIsError ? .orange : .green)
                            .multilineTextAlignment(.center)
                    } else if model.healthDenied {
                        Text("Health access is off — allow Onigiri in the Health app on your iPhone.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .controlSize(.small)
                .padding(.horizontal, 4)
            }
            .navigationTitle("🍙 Onigiri")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showMeals) {
                MealPickerView(model: model)
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshIfStale() }
            }
        }
    }

    /// Fixed 32pt ignored the watch text-size setting (the phone's
    /// headline got the same fix in 1.7); minimumScaleFactor below
    /// keeps huge sizes on one line.
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 32.0

    /// Mirrors the phone's Today headline setting through the same shared
    /// readout: kcal left / balance / eaten / budget.
    @ViewBuilder
    private var headlineNumber: some View {
        let readout = CalorieBudget.headlineReadout(
            mode: HeadlineMode(rawValue: balanceStyle) ?? .remaining,
            summary: model.state.summary,
            dailyBudgetKcal: model.state.dailyBudgetKcal
        )
        let valueFormat: FloatingPointFormatStyle<Double> = readout.signed
            ? .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))
            : .number.precision(.fractionLength(0))
        VStack(spacing: 0) {
            Text(readout.value, format: valueFormat)
                .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                .foregroundStyle(readout.tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(readout.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        // Carry the near/over budget (or deficit/surplus) status the tint
        // alone can't (remainingStatusLabel discipline).
        .accessibilityElement(children: .combine)
        .accessibilityValue(readout.statusLabel ?? "")
    }
}

/// The "Log" sheet: the phone's default Log view in miniature —
/// Favorites first (meals + foods mixed), then Recent, one unified
/// list, one tap to log. NO Meal-or-Food chooser (ruled out
/// 2026-07-14: an extra tap per log on the tappiest device); a
/// non-favorited meal reaches the watch the moment it's starred or
/// logged, exactly like the phone's Favorites scope. The separate
/// Favorites/Meals/Foods pages were dropped in 1.9.1; the standalone
/// all-Meals section followed in 2.1.
struct MealPickerView: View {
    let model: WatchModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.sync.favorites.isEmpty && model.sync.recentFoods.isEmpty {
                    Text("Add favorites or log food in app")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.flashIsError, let flash = model.flash {
                    Text(flash)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                // Favorites lead — meals and foods mixed, like the
                // phone's default scope (and its dropped browse page
                // folds in here).
                if !model.sync.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(model.sync.favorites.prefix(6).map { $0 }) { item in
                            row(item)
                        }
                    }
                }
                // The phone's most recently logged foods — one serving,
                // one tap, same path as favorites.
                if !model.sync.recentFoods.isEmpty {
                    Section("Recent") {
                        ForEach(model.sync.recentFoods.prefix(6).map { $0 }) { food in
                            row(food)
                        }
                    }
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ meal: SyncedMeal) -> some View {
        LogItemRow(model: model, item: meal) {
            // Failure keeps the picker open — dismissing on error
            // looked identical to success.
            dismiss()
        }
    }
}

/// One tappable synced item — logs a serving through the shared path.
private struct LogItemRow: View {
    let model: WatchModel
    let item: SyncedMeal
    var onSuccess: (() -> Void)? = nil

    // The secondary caption follows the phone's first tracked slot —
    // the slot keys already ride the sync context into shared defaults,
    // and every synced item carries its nutrients.
    @AppStorage(SharedStore.trackedMetric1Key, store: SharedStore.defaults) private var trackedMetric1 = "sodium"
    @AppStorage(SharedStore.trackedMetric2Key, store: SharedStore.defaults) private var trackedMetric2 = "water"

    private var metric: TrackedNutrient {
        .firstFoodMetric(slot1: trackedMetric1, slot2: trackedMetric2)
    }

    private var metricAmount: Double {
        metric.itemAmount(sodiumMg: item.sodiumMg, nutrients: item.nutrients ?? NutrientValues()) ?? 0
    }

    var body: some View {
        Button {
            Task {
                if await model.log(item) {
                    onSuccess?()
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text("\(item.kcal, format: .number.precision(.fractionLength(0))) kcal • \(metricAmount, format: .number.precision(.fractionLength(0...1))) \(metric.captionUnit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    WatchHomeView(model: WatchModel())
}
