import SwiftUI
import OnigiriKit

/// Watch home: the onigiri gauge and balance, with one-tap water and meal
/// logging. Meals and settings sync from the iPhone.
struct WatchHomeView: View {
    @State private var model = WatchModel()
    @State private var showMeals = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    // Gauge and balance share a line so both buttons fit on
                    // one screen without scrolling.
                    HStack(spacing: 10) {
                        OnigiriGauge(progress: model.state.gaugeProgress)
                            .frame(width: 44, height: 44)
                        Text(model.state.summary.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(model.state.summary.balanceKcal <= 0 ? Color.green : Color.orange)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }

                    Button {
                        showMeals = true
                    } label: {
                        Label("Log a meal", systemImage: "fork.knife")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        Task { await model.logWater() }
                    } label: {
                        Label("Add \(model.waterServingOz, format: .number.precision(.fractionLength(0))) oz", systemImage: "drop.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
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

}

/// Synced meals, one tap to log.
struct MealPickerView: View {
    let model: WatchModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.sync.meals.isEmpty {
                    Text("Save meals on your iPhone and they'll sync here for one-tap logging.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.sync.meals) { meal in
                    Button {
                        Task {
                            await model.log(meal)
                            dismiss()
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
    WatchHomeView()
}
