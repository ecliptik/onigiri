import SwiftUI

/// Watch home: glanceable balance plus one-tap logging.
/// Phase 6 wires this to HealthKit and the synced meal library.
struct WatchHomeView: View {
    private let balance: Double = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(balance, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("kcal balance")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        // Phase 6: log one water serving
                    } label: {
                        Label("Water", systemImage: "drop.fill")
                    }
                    .tint(.blue)

                    Button {
                        // Phase 6: pick a saved meal
                    } label: {
                        Label("Meal", systemImage: "fork.knife")
                    }
                    .tint(.orange)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Onigiri")
        }
    }
}

#Preview {
    WatchHomeView()
}
