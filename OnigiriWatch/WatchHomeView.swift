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
                            // The serving on the face, like the phone
                            // widget's water button.
                            Text("Log water (\(model.waterServingOz, format: .number.precision(.fractionLength(0))) oz)")
                        } icon: {
                            WaterIconView(raw: waterIcon)
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

/// Synced meals, one tap to log.
struct MealPickerView: View {
    let model: WatchModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.sync.meals.isEmpty {
                    Text("Save meals on your iPhone and they'll appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.flashIsError, let flash = model.flash {
                    Text(flash)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                ForEach(model.sync.meals) { meal in
                    Button {
                        Task {
                            // Failure keeps the picker open — dismissing
                            // on error looked identical to success.
                            if await model.log(meal) {
                                dismiss()
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.name)
                            Text("\(meal.kcal, format: .number.precision(.fractionLength(0))) kcal • \(meal.sodiumMg, format: .number.precision(.fractionLength(0))) mg Na")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Meals")
        }
    }
}

#Preview {
    WatchHomeView(model: WatchModel())
}
