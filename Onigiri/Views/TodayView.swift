import SwiftUI
import OnigiriKit

/// Home screen: the daily calorie meter, live from HealthKit.
struct TodayView: View {
    @State private var model = TodayModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    balanceHeadline
                    meterGrid
                    hydrationRow

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Today")
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Seed sample data", systemImage: "testtube.2") {
                        Task { await model.seedSampleData() }
                    }
                }
            }
            #endif
        }
        .task { await model.start() }
        .refreshable { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }

    private var balanceHeadline: some View {
        VStack(spacing: 4) {
            Text(model.summary.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(model.summary.balanceKcal <= 0 ? Color.green : Color.orange)
                .contentTransition(.numericText())
            Text("kcal balance today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 32)
    }

    private var meterGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MeterCell(label: "Intake", value: model.summary.intakeKcal, systemImage: "fork.knife", tint: .orange)
                MeterCell(label: "Active", value: model.summary.activeBurnKcal, systemImage: "flame.fill", tint: .red)
                MeterCell(label: "Resting", value: model.summary.restingBurnKcal, systemImage: "bed.double.fill", tint: .indigo)
            }
        }
        .padding(.horizontal)
    }

    private var hydrationRow: some View {
        HStack(spacing: 12) {
            Label {
                Text("\(model.summary.sodiumMg, format: .number.precision(.fractionLength(0))) mg sodium")
            } icon: {
                Image(systemName: "aqi.medium").foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity)

            Label {
                Text("\(model.summary.waterOz, format: .number.precision(.fractionLength(0))) oz water")
            } icon: {
                Image(systemName: "drop.fill").foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
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
                .contentTransition(.numericText())
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
