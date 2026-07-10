import SwiftUI
import OnigiriKit

/// Water tracking: progress ring toward the daily goal, one-tap serving add.
struct WaterView: View {
    @AppStorage(SharedStore.waterServingKey, store: SharedStore.defaults) private var servingOz = 12.0
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var goalOz = 64.0
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "drop"

    private var waterEmoji: String { waterIcon == "wave" ? "🌊" : "💧" }

    /// Dynamic Type for the ring's headline number.
    @ScaledMetric(relativeTo: .largeTitle) private var ringNumberSize = 44.0

    @State private var model = WaterModel()
    @State private var toastCenter = ToastCenter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Layout.screenSpacing) {
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
            .navigationTitle(dayTitle)
            // Settings has one predictable home: the gear on Today (HIG
            // consistency — don't scatter entry points per tab).
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await model.goToPreviousDay() }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous day")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.goToNextDay() }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(model.isToday)
                    .accessibilityLabel("Next day")
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -60 {
                        Task { await model.goToNextDay() }
                    } else if value.translation.width > 60 {
                        Task { await model.goToPreviousDay() }
                    }
                }
            )
        }
        .task { await model.refresh() }
        .onAppear { Task { await model.refresh() } }
        .refreshable { await model.refresh() }
        .onChange(of: toastCenter.mutationVersion) { _, _ in
            Task { await model.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }

    /// "Water" on today keeps the tab's identity; browsed days say which.
    private var dayTitle: String {
        if model.isToday { return "Water" }
        if Calendar.current.isDateInYesterday(model.selectedDate) { return "Yesterday" }
        return model.selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
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
                    .font(.system(size: ringNumberSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
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
                    Text("Log \(servingOz, format: .number.precision(.fractionLength(0))) oz")
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
                // Looks like the control it is (HIG: visible affordance).
                Label("Other amount", systemImage: "chevron.up.chevron.down")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
    }

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log")
                .font(.sectionHeader)
                .padding(.horizontal)

            if model.entries.isEmpty {
                Text(model.isToday
                     ? "Nothing yet — tap the button when you finish a glass."
                     : "No water was logged this day.")
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
                    .accessibilityLabel("Delete \(Int(entry.oz)) ounce entry")
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    WaterView()
}
