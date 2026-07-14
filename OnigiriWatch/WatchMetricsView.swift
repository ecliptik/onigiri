import SwiftUI
import OnigiriKit

/// The second watch page (swipe from home): the phone's two tracked-
/// metric slots, same read as Today's row — limit mode shows the total
/// colored toward the ceiling, goal mode "x / target", green when met.
struct WatchMetricsView: View {
    let model: WatchModel

    // AppStorage so a slot sync re-renders immediately (values land in
    // the shared defaults via WatchSync.store).
    @AppStorage(SharedStore.trackedMetric1Key, store: SharedStore.defaults) private var trackedMetric1 = "sodium"
    @AppStorage(SharedStore.trackedMetric1ModeKey, store: SharedStore.defaults) private var trackedMetric1Mode = ""
    @AppStorage(SharedStore.trackedMetric1TargetKey, store: SharedStore.defaults) private var trackedMetric1Target = 0.0
    @AppStorage(SharedStore.trackedMetric1IconKey, store: SharedStore.defaults) private var trackedMetric1Icon = ""
    @AppStorage(SharedStore.trackedMetric2Key, store: SharedStore.defaults) private var trackedMetric2 = "water"
    @AppStorage(SharedStore.trackedMetric2ModeKey, store: SharedStore.defaults) private var trackedMetric2Mode = ""
    @AppStorage(SharedStore.trackedMetric2TargetKey, store: SharedStore.defaults) private var trackedMetric2Target = 0.0
    @AppStorage(SharedStore.trackedMetric2IconKey, store: SharedStore.defaults) private var trackedMetric2Icon = ""
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var waterGoalOz = 64.0

    var body: some View {
        NavigationStack {
            // ScrollView root, always — a bare VStack under a navigation
            // title renders blank on-device.
            ScrollView {
                VStack(spacing: 8) {
                    goalLine
                    let first = slotNutrient(1)
                    let second = slotNutrient(2)
                    if first == nil && second == nil {
                        Text("No tracked metrics — customize them in the iPhone app's Settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if let first {
                        metricCard(slot: 1, nutrient: first)
                    }
                    if let second {
                        metricCard(slot: 2, nutrient: second)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Metrics")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // Page swipes re-fire this (and TabView pre-renders
            // neighbors) — the model skips when fresh.
            Task { await model.refreshIfStale() }
        }
    }

    /// The goal card's one-liner, from state the page already loads.
    @ViewBuilder
    private var goalLine: some View {
        if let target = model.state.deficitTargetKcal, target > 0 {
            let banked = max(0, -model.state.summary.balanceKcal)
            let percent = Int(min(1, banked / target) * 100)
            VStack(spacing: 0) {
                Text("Daily goal \(percent)%")
                    .font(.headline)
                    .foregroundStyle(percent >= 100 ? Color.green : Color.primary)
                Text("\(banked, format: .number.precision(.fractionLength(0))) of \(target, format: .number.precision(.fractionLength(0))) kcal deficit")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        }
    }

    private func slotNutrient(_ slot: Int) -> TrackedNutrient? {
        let raw = slot == 1 ? trackedMetric1 : trackedMetric2
        if raw == SharedStore.trackedMetricNone { return nil }
        return TrackedNutrient(key: raw) ?? (slot == 1 ? .sodium : .water)
    }

    private func metricCard(slot: Int, nutrient: TrackedNutrient) -> some View {
        let storedMode = slot == 1 ? trackedMetric1Mode : trackedMetric2Mode
        let mode = TrackedMetricMode(rawValue: storedMode) ?? nutrient.defaultMode
        let target = trackedTarget(slot: slot, nutrient: nutrient)
        let total = model.trackedTotals[slot - 1]
        let met = total >= target
        let valueColor: Color = mode == .limit
            ? Color.sodiumStatus(mg: total, limitMg: target)
            : (met ? .green : .primary)
        // Color-only on screen by ruling (the user vetoed visible
        // status words); VoiceOver hears it via the card's value.
        let status = mode == .limit
            ? Color.sodiumStatusLabel(mg: total, limitMg: target)
            : nil

        return HStack(spacing: 8) {
            metricIcon(slot: slot, nutrient: nutrient)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 0) {
                Text(mode == .limit
                    ? "\(total.formatted(.number.precision(.fractionLength(0)))) \(nutrient.unitSymbol)"
                    : "\(total.formatted(.number.precision(.fractionLength(0)))) / \(target.formatted(.number.precision(.fractionLength(0)))) \(nutrient.unitSymbol)")
                    .font(.headline)
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(nutrient.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .accessibilityValue(status ?? "")
    }

    /// Sodium/water targets ride their long-standing synced keys.
    private func trackedTarget(slot: Int, nutrient: TrackedNutrient) -> Double {
        switch nutrient {
        case .sodium: return sodiumLimitMg
        case .water: return waterGoalOz
        default:
            let stored = slot == 1 ? trackedMetric1Target : trackedMetric2Target
            return stored > 0 ? stored : nutrient.defaultTarget
        }
    }

    @ViewBuilder
    private func metricIcon(slot: Int, nutrient: TrackedNutrient) -> some View {
        if nutrient == .water {
            WaterIconView(raw: waterIcon)
        } else {
            let stored = slot == 1 ? trackedMetric1Icon : trackedMetric2Icon
            Text(SharedStore.isCustomEmoji(stored) ? stored : nutrient.defaultEmoji)
        }
    }
}
