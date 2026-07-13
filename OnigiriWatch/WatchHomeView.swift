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
    @AppStorage(SharedStore.balanceStyleKey, store: SharedStore.defaults) private var balanceStyle = "balance"

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
                            Text("Log a meal")
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
                Task { await model.refresh() }
            }
        }
    }

    /// Mirrors the phone's Today headline setting: ± balance, or kcal left
    /// toward the deficit goal when the user picked the countdown.
    @ViewBuilder
    private var headlineNumber: some View {
        if balanceStyle == "remaining", let remaining = model.state.remainingKcal {
            let headline = CalorieBudget.remainingHeadline(remaining)
            VStack(spacing: 0) {
                Text(headline.value, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.remainingStatus(kcal: remaining))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(headline.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(model.state.summary.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(model.state.summary.balanceKcal <= 0 ? Color.green : Color.orange)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}

/// The "Log a meal" sheet: the original quick page — synced meals plus
/// the six most recent foods, one tap to log. The deeper Favorites/
/// Meals/Foods browsing lives on the app's own pages past Metrics.
struct MealPickerView: View {
    let model: WatchModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.sync.meals.isEmpty && model.sync.recentFoods.isEmpty {
                    Text("Save meals on your iPhone and they'll appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.flashIsError, let flash = model.flash {
                    Text(flash)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if !model.sync.meals.isEmpty {
                    Section(model.sync.recentFoods.isEmpty ? "" : "Meals") {
                        ForEach(model.sync.meals) { meal in
                            row(meal)
                        }
                    }
                }
                // The phone's most recently logged foods — one serving,
                // one tap, same path as meals.
                if !model.sync.recentFoods.isEmpty {
                    // Six here — the Foods page has the full ten.
                    Section("Recent foods") {
                        ForEach(model.sync.recentFoods.prefix(6).map { $0 }) { food in
                            row(food)
                        }
                    }
                }
            }
            .navigationTitle("Log")
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

/// One top-level browse page (Favorites / Meals / Foods): the ten most
/// recent of its scope, one tap to log — the flash confirms in place,
/// there's no sheet to dismiss.
struct LogScopeView: View {
    let model: WatchModel
    let title: String
    let items: [SyncedMeal]
    let empty: String

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text(empty)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let flash = model.flash {
                    Text(flash)
                        .font(.footnote)
                        .foregroundStyle(model.flashIsError ? .orange : .green)
                }
                ForEach(items) { item in
                    LogItemRow(model: model, item: item)
                }
            }
            .navigationTitle(title)
        }
    }
}

/// One tappable synced item — logs a serving through the shared path.
private struct LogItemRow: View {
    let model: WatchModel
    let item: SyncedMeal
    var onSuccess: (() -> Void)? = nil

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
                Text("\(item.kcal, format: .number.precision(.fractionLength(0))) kcal • \(item.sodiumMg, format: .number.precision(.fractionLength(0))) mg Na")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    WatchHomeView(model: WatchModel())
}
