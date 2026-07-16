import WidgetKit
import SwiftUI
import OnigiriKit

/// Home-screen widget: the top of Today, mirrored — the kcal-left ring
/// with Burned/Eaten flanking, the tracked-metric pills, the rice-paper
/// canvas — plus a prominent Log button that deep-links into the Log
/// sheet. Small/medium/large.
///
/// The interactive ‹ › day paging and in-place water button were removed
/// after on-device testing: WidgetKit AppIntent buttons wouldn't dispatch
/// on the device (they no-op'd / flashed), while the Log deep link (a
/// Link/openURL, not an intent) works reliably — so the widget keeps the
/// glance and the one working action.
struct TodayCardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.todayCard, provider: TodayCardProvider()) { entry in
            TodayCardView(entry: entry)
                .containerBackground(Color.riceCanvas, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's balance, burned and eaten, and your tracked metrics.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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

/// The Log-sheet deep link (onigiri://log → the app opens the Log sheet
/// for today). A Link/openURL, not an AppIntent — this dispatches on the
/// device where interactive widget intents didn't.
private let logURL = URL(string: "onigiri://log")!

struct TodayCardView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayCardEntry

    private var snapshot: DaySnapshot { entry.snapshot }
    private var summary: DailyEnergySummary { snapshot.summary }
    private var isLarge: Bool { family == .systemLarge }
    private var isSmall: Bool { family == .systemSmall }

    var body: some View {
        if snapshot.needsSetup {
            setup
        } else if isSmall {
            // Small: the ring glance, whole widget taps into the Log sheet.
            ringedHeadline
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetURL(logURL)
        } else if isLarge {
            VStack(spacing: 12) {
                header
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    energyFlank(summary.totalBurnKcal, "Burned")
                    ringedHeadline
                    energyFlank(summary.intakeKcal, "Eaten")
                }
                Spacer(minLength: 0)
                trackedMetricsRow
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                header
                HStack(spacing: 14) {
                    ringedHeadline
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            miniFlank(summary.totalBurnKcal, "Burned")
                            miniFlank(summary.intakeKcal, "Eaten")
                        }
                        trackedMetricsRow
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var setup: some View {
        VStack(spacing: 8) {
            OnigiriGauge(progress: 0)
                .frame(width: isSmall ? 48 : 64, height: isSmall ? 48 : 64)
            Text("Open Onigiri to set up")
                .font(isSmall ? .caption2 : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header (title + prominent Log button)

    private var header: some View {
        HStack(spacing: 8) {
            Text("Today")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            // The one action: bigger, labeled, ricePaper — deep-links
            // into the Log sheet.
            Link(destination: logURL) {
                Label("Log", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.onRicePaper)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.ricePaper, in: .capsule)
            }
            .accessibilityLabel("Log food or water")
        }
    }

    // MARK: - Ring

    /// Today's headline ring: how much of the day's calorie budget is
    /// eaten, orange when over. Without a plan the plain headline renders.
    @ViewBuilder
    private var ringedHeadline: some View {
        if let budget = snapshot.planState.dailyBudgetKcal, budget > 0 {
            let eaten = min(1, max(0, summary.intakeKcal / budget))
            let over = summary.intakeKcal > budget
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: isSmall ? 5 : 6)
                Circle()
                    .trim(from: 0, to: eaten)
                    .stroke(
                        over ? Color.orange : Color.riceToast,
                        style: StrokeStyle(lineWidth: isSmall ? 5 : 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                headline
                    .padding(isLarge ? 22 : (isSmall ? 14 : 12))
            }
            .frame(width: ringSize, height: ringSize)
            .accessibilityElement(children: .combine)
            .accessibilityValue("\((eaten * 100).formatted(.number.precision(.fractionLength(0)))) percent of today's budget eaten\(remainingStatusValue.map { ", \($0)" } ?? "")")
        } else {
            headline
                .accessibilityElement(children: .combine)
                .accessibilityValue(remainingStatusValue ?? "")
        }
    }

    /// VoiceOver twin of the headline's amber "near budget" tint — the
    /// warning is otherwise color-only (remainingStatusLabel discipline).
    private var remainingStatusValue: String? {
        guard SharedStore.showsRemainingKcal, let remaining = snapshot.remainingKcal else { return nil }
        return Color.remainingStatusLabel(kcal: remaining)
    }

    /// One scaled metric so ring and headline track Larger Text
    /// together (Dynamic Type backfill; family ratios hold, the
    /// existing minimumScaleFactors absorb the extremes).
    @ScaledMetric(relativeTo: .largeTitle) private var textScale = 1.0
    private var ringSize: CGFloat { (isLarge ? 168 : (isSmall ? 118 : 104)) * min(textScale, 1.3) }
    private var headlineSize: CGFloat { (isLarge ? 44 : (isSmall ? 30 : 26)) * textScale }

    /// The headline number in the user's chosen style.
    private var headline: some View {
        VStack(spacing: 2) {
            if SharedStore.showsRemainingKcal, let remaining = snapshot.remainingKcal {
                let headline = CalorieBudget.remainingHeadline(remaining)
                Text(headline.value, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Color.remainingStatus(kcal: remaining))
                Text(headline.caption)
                    .font(isLarge ? .caption : .caption2)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                Text(summary.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                    .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(summary.balanceKcal <= 0 ? Color.green : Color.orange)
                Text("kcal balance")
                    .font(isLarge ? .caption : .caption2)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One side of the ring: total burned or eaten kcal (large layout).
    private func energyFlank(_ value: Double, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// The medium family's one-line flank: "1,505 Burned".
    private func miniFlank(_ value: Double, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.footnote.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    // MARK: - Tracked metrics

    /// The two configurable tracked-metric pills (sodium and water by
    /// default). Large lays them side by side, medium stacks them.
    @ViewBuilder
    private var trackedMetricsRow: some View {
        let first = SharedStore.trackedNutrient(slot: 1)
        let second = SharedStore.trackedNutrient(slot: 2)
        if first != nil || second != nil {
            let layout = isLarge
                ? AnyLayout(HStackLayout(spacing: 10))
                : AnyLayout(VStackLayout(spacing: 6))
            layout {
                if let first {
                    trackedMetricPill(slot: 1, nutrient: first)
                }
                if let second {
                    trackedMetricPill(slot: 2, nutrient: second)
                }
            }
            .font(isLarge ? .footnote : .caption)
        }
    }

    /// One tracked metric, pill-shaped like Today's progress-gauges mode.
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
