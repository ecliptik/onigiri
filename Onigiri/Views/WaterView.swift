import SwiftUI
import OnigiriKit

/// Water tracking: progress ring toward the daily goal, one-tap serving add.
struct WaterView: View {
    @AppStorage(SharedStore.waterServingKey, store: SharedStore.defaults) private var servingOz = 12.0
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var goalOz = 64.0
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "drop"

    private var waterEmoji: String { waterIcon == "wave" ? "🌊" : "💧" }

    @State private var model = WaterModel()
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ring
                    addButtons
                    entriesList

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Water")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Water settings", systemImage: "gearshape") {
                        showSettings = true
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                WaterSettingsView(servingOz: $servingOz, goalOz: $goalOz)
                    .presentationDetents([.medium])
            }
        }
        .task { await model.refresh() }
        .onAppear { Task { await model.refresh() } }
        .refreshable { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 16)
            Circle()
                .trim(from: 0, to: min(1, goalOz > 0 ? model.totalOz / goalOz : 0))
                .stroke(.blue, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: model.totalOz)
            VStack(spacing: 2) {
                Text(model.totalOz, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("of \(goalOz, format: .number.precision(.fractionLength(0))) oz")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 190, height: 190)
        .padding(.top, 24)
    }

    private var addButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await model.add(oz: servingOz) }
            } label: {
                Label {
                    Text("Add \(servingOz, format: .number.precision(.fractionLength(0))) oz")
                } icon: {
                    Text(waterEmoji)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal)

            Menu {
                ForEach([8.0, 12, 16, 20, 24, 32], id: \.self) { oz in
                    Button("\(oz, format: .number.precision(.fractionLength(0))) oz") {
                        Task { await model.add(oz: oz) }
                    }
                }
            } label: {
                Text("Other amount")
                    .font(.subheadline)
            }
        }
    }

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)
                .padding(.horizontal)

            if model.entries.isEmpty {
                Text("Nothing yet — tap the button when you finish a glass.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            ForEach(model.entries) { entry in
                HStack {
                    Text(waterEmoji)
                    Text(entry.date, style: .time)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(entry.oz, format: .number.precision(.fractionLength(0))) oz")
                        .monospacedDigit()
                    Button {
                        Task { await model.delete(entry) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
}

struct WaterSettingsView: View {
    @Binding var servingOz: Double
    @Binding var goalOz: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $servingOz, in: 4...40, step: 2) {
                    LabeledContent("Serving size") {
                        Text("\(servingOz, format: .number.precision(.fractionLength(0))) oz")
                    }
                }
                Stepper(value: $goalOz, in: 16...200, step: 8) {
                    LabeledContent("Daily goal") {
                        Text("\(goalOz, format: .number.precision(.fractionLength(0))) oz")
                    }
                }
            }
            .navigationTitle("Water Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    WaterView()
}
