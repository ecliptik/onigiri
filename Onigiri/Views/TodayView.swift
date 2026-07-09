import SwiftUI

/// Home screen: the daily calorie meter.
/// Phase 2 wires these numbers to HealthKit; for now the layout renders with
/// placeholder zeros so the app boots and the design can be iterated on.
struct TodayView: View {
    private let intake: Double = 0
    private let activeBurn: Double = 0
    private let restingBurn: Double = 0

    private var balance: Double { intake - (activeBurn + restingBurn) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text(balance, format: .number.precision(.fractionLength(0)))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("kcal balance today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            MeterCell(label: "Intake", value: intake, systemImage: "fork.knife", tint: .orange)
                            MeterCell(label: "Active", value: activeBurn, systemImage: "flame.fill", tint: .red)
                            MeterCell(label: "Resting", value: restingBurn, systemImage: "bed.double.fill", tint: .indigo)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Today")
        }
    }
}

struct MeterCell: View {
    let label: String
    let value: Double
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
    }
}

#Preview {
    TodayView()
}
