import WidgetKit
import SwiftUI
import OnigiriKit

/// Large home-screen widget: the top of Today, mirrored — the kcal-left
/// ring with Burned/Eaten flanking, the tracked-metric pills, the
/// rice-paper canvas.
struct TodayCardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.todayCard, provider: TodayCardProvider()) { entry in
            TodayCardView(entry: entry)
                .containerBackground(Color.riceCanvas, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's balance, burned and eaten, and your tracked metrics.")
        .supportedFamilies([.systemLarge])
    }
}

struct TodayCardEntry: TimelineEntry {
    let date: Date
    let snapshot: DaySnapshot
}

struct TodayCardProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayCardEntry {
        TodayCardEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayCardEntry) -> Void) {
        // The gallery gets the flattering placeholder, not a fresh
        // install's zeros (or a watchdog fallback from a slow query).
        if context.isPreview {
            completion(TodayCardEntry(date: .now, snapshot: .placeholder))
            return
        }
        Task { @MainActor in
            completion(TodayCardEntry(date: .now, snapshot: await SnapshotLoader.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayCardEntry>) -> Void) {
        Task { @MainActor in
            let now = Date()
            let snapshot = await SnapshotLoader.load()
            // Push-based reloads keep widgets fresh; this poll is only a fallback.
            let refresh = now.addingTimeInterval(WidgetRefreshPolicy.pollFallback)
            if let midnight = nextMidnight(after: now), midnight <= refresh {
                completion(Timeline(
                    entries: [
                        TodayCardEntry(date: now, snapshot: snapshot),
                        TodayCardEntry(date: midnight, snapshot: snapshot.newDay),
                    ],
                    policy: .after(midnight)
                ))
            } else {
                completion(Timeline(
                    entries: [TodayCardEntry(date: now, snapshot: snapshot)],
                    policy: .after(refresh)
                ))
            }
        }
    }
}

struct TodayCardView: View {
    let entry: TodayCardEntry

    private var snapshot: DaySnapshot { entry.snapshot }
    private var summary: DailyEnergySummary { snapshot.summary }

    var body: some View {
        if snapshot.needsSetup {
            VStack(spacing: 8) {
                OnigiriGauge(progress: 0)
                    .frame(width: 64, height: 64)
                Text("Open Onigiri to set up")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    energyFlank(summary.totalBurnKcal, "Burned")
                    ringedHeadline
                    energyFlank(summary.intakeKcal, "Eaten")
                }
                trackedMetricsRow
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Ring

    /// Today's headline ring, in miniature: how much of the day's calorie
    /// budget is eaten, orange when over. Without a plan the plain
    /// headline renders, exactly like Today.
    @ViewBuilder
    private var ringedHeadline: some View {
        if let budget = snapshot.planState.dailyBudgetKcal, budget > 0 {
            let eaten = min(1, max(0, summary.intakeKcal / budget))
            let over = summary.intakeKcal > budget
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: eaten)
                    .stroke(
                        over ? Color.orange : Color.riceToast,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                headline
                    .padding(22)
            }
            // Fixed like Today's 190pt ring (scaled to the widget's
            // canvas) — an HStack-share ring drifted with flank width
            // and squeezed the headline into truncation.
            .frame(width: 176, height: 176)
            .accessibilityElement(children: .combine)
            .accessibilityValue("\((eaten * 100).formatted(.number.precision(.fractionLength(0)))) percent of today's budget eaten")
        } else {
            headline
        }
    }

    /// The headline number in the user's chosen style (same "Calorie
    /// display" setting as the app/watch).
    private var headline: some View {
        VStack(spacing: 2) {
            if SharedStore.showsRemainingKcal, let remaining = snapshot.remainingKcal {
                let headline = CalorieBudget.remainingHeadline(remaining)
                Text(headline.value, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Color.remainingStatus(kcal: remaining))
                    .invalidatableContent()
                Text(headline.caption)
                    .font(.caption)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                Text(summary.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(summary.balanceKcal <= 0 ? Color.green : Color.orange)
                    .invalidatableContent()
                Text("kcal balance")
                    .font(.caption)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One side of the ring: total burned or eaten kcal, like Today's
    /// compact energy mode.
    private func energyFlank(_ value: Double, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .invalidatableContent()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tracked metrics

    /// The two configurable tracked-metric pills (sodium and water by
    /// default) — a slot set to None disappears; a lone survivor centers.
    @ViewBuilder
    private var trackedMetricsRow: some View {
        let first = SharedStore.trackedNutrient(slot: 1)
        let second = SharedStore.trackedNutrient(slot: 2)
        if first != nil || second != nil {
            HStack(spacing: 10) {
                if let first {
                    trackedMetricPill(slot: 1, nutrient: first)
                }
                if let second {
                    trackedMetricPill(slot: 2, nutrient: second)
                }
            }
            .font(.footnote)
        }
    }

    /// One tracked metric, pill-shaped like Today's progress-gauges mode:
    /// limit mode reads and colors like sodium always has, goal mode like
    /// water ("x / target", green when met); the soft fill is the
    /// fraction of the target reached.
    private func trackedMetricPill(slot: Int, nutrient: TrackedNutrient) -> some View {
        let mode = SharedStore.trackedMode(slot: slot, nutrient: nutrient)
        let target = SharedStore.trackedTarget(slot: slot, nutrient: nutrient)
        let total = snapshot.trackedTotal(slot: slot)
        let met = total >= target
        let tint: Color = mode == .limit
            ? Color.sodiumStatus(mg: total, limitMg: target)
            : (nutrient == .water ? .blue : .green)

        return Label {
            switch mode {
            case .limit:
                // Color-only, like Today (the traffic light IS the
                // status); VoiceOver still hears it via the value.
                Text("\(total, format: .number.precision(.fractionLength(0))) \(nutrient.unitSymbol) \(nutrient.inlineName)")
                    .foregroundStyle(Color.sodiumStatus(mg: total, limitMg: target))
                    .fontWeight(.medium)
                    .accessibilityValue(Color.sodiumStatusLabel(mg: total, limitMg: target) ?? "")
            case .goal:
                Text("\(total, format: .number.precision(.fractionLength(0))) / \(target, format: .number.precision(.fractionLength(0))) \(nutrient.unitSymbol) \(nutrient.inlineName)")
                    .foregroundStyle(met ? Color.green : Color.secondary)
                    .fontWeight(met ? .medium : .regular)
            }
        } icon: {
            if nutrient == .water {
                WaterIconView(raw: SharedStore.defaults.string(forKey: SharedStore.waterIconKey) ?? "")
            } else {
                Text(SharedStore.trackedEmoji(slot: slot, nutrient: nutrient))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .invalidatableContent()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 9)
                    .fill(tint.opacity(0.18))
                    .frame(width: geo.size.width * min(1, max(0, target > 0 ? total / target : 0)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 9))
    }
}
