import SwiftUI
import OnigiriKit

/// Watch home: glanceable balance plus one-tap logging.
/// Phase 7 adds one-tap water/meals and library sync; for now this
/// requests HealthKit access (which the complications rely on) and
/// shows the live balance.
struct WatchHomeView: View {
    @State private var balance: Double = 0
    @State private var waterOz: Double = 0

    private let health = HealthKitService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(balance, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(balance <= 0 ? Color.green : Color.orange)
                Text("kcal balance")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Label {
                    Text("\(waterOz, format: .number.precision(.fractionLength(0))) oz")
                } icon: {
                    Image(systemName: "drop.fill").foregroundStyle(.blue)
                }
                .font(.footnote)
            }
            .navigationTitle("Onigiri")
        }
        .task {
            guard HealthKitService.isAvailable else { return }
            if (try? await health.shouldRequestAuthorization()) == true {
                try? await health.requestAuthorization()
            }
            if let summary = try? await health.todaySummary() {
                balance = summary.balanceKcal
                waterOz = summary.waterOz
            }
        }
    }
}

#Preview {
    WatchHomeView()
}
