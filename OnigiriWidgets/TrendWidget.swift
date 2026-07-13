import WidgetKit
import SwiftUI
import Charts
import OnigiriKit

// MARK: - Weight trend

struct TrendEntry: TimelineEntry {
    let date: Date
    let points: [WeightTrend.Point]
    let smoothed: [WeightTrend.Point]
    let targetLb: Double?
    let needsSetup: Bool

    static var placeholder: TrendEntry {
        // A gently descending month for the gallery.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let points: [WeightTrend.Point] = (0..<30).compactMap { offset -> WeightTrend.Point? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let wobble = Double((offset * 7) % 5) * 0.3 - 0.6
            return WeightTrend.Point(date: day, weightLb: 199 + Double(offset) * 0.12 + wobble)
        }.reversed().map { $0 }
        return TrendEntry(
            date: .now,
            points: points,
            smoothed: WeightTrend.movingAverage(points, windowDays: 7),
            targetLb: 190,
            needsSetup: false
        )
    }
}

struct TrendProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrendEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TrendEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { @MainActor in
            completion(await load())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrendEntry>) -> Void) {
        Task { @MainActor in
            let entry = await load()
            // Weigh-ins arrive at most a few times a day.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(2 * 60 * 60))))
        }
    }

    @MainActor
    private func load() async -> TrendEntry {
        let health = HealthKitService()
        let needsSetup = (try? await health.shouldRequestAuthorization()) == true
        let points = (try? await health.bodyMassHistory(days: 90)) ?? []
        return TrendEntry(
            date: .now,
            points: points,
            smoothed: WeightTrend.movingAverage(points, windowDays: 7),
            targetLb: WatchSync.loadGoal()?.targetWeightLb,
            needsSetup: needsSetup
        )
    }
}

struct TrendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnigiriTrend", provider: TrendProvider()) { entry in
            TrendWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weight Trend")
        .description("Weigh-ins, the 7-day average, and your target.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// The Goal tab's chart, widget-sized: raw weigh-ins as faint points,
/// the smoothed line, and the dashed target.
struct TrendWidgetView: View {
    let entry: TrendEntry

    var body: some View {
        if entry.needsSetup {
            VStack(spacing: 6) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Open Onigiri to set up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if entry.points.count < 2 {
            VStack(spacing: 6) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Weigh-ins chart here once Apple Health has a few days of data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            Chart {
                ForEach(Array(entry.points.enumerated()), id: \.offset) { _, point in
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.weightLb)
                    )
                    .foregroundStyle(.secondary)
                    .opacity(0.35)
                    .symbolSize(10)
                }
                ForEach(Array(entry.smoothed.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("7-day average", point.weightLb)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }
                if let target = entry.targetLb {
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis(.hidden)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let weights = entry.points.map(\.weightLb) + [entry.targetLb].compactMap(\.self)
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        return (min - 2)...(max + 2)
    }
}

// MARK: - Daily progress combo

struct ProgressEntry: TimelineEntry {
    let date: Date
    let snapshot: DaySnapshot
    let streak: Int

    static let placeholder = ProgressEntry(date: .now, snapshot: .placeholder, streak: 3)
}

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { @MainActor in
            completion(await load())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        Task { @MainActor in
            let now = Date()
            let entry = await load()
            let refresh = now.addingTimeInterval(30 * 60)
            if let midnight = nextMidnight(after: now), midnight <= refresh {
                completion(Timeline(
                    entries: [entry, ProgressEntry(date: midnight, snapshot: entry.snapshot.newDay, streak: entry.streak)],
                    policy: .after(midnight)
                ))
            } else {
                completion(Timeline(entries: [entry], policy: .after(refresh)))
            }
        }
    }

    @MainActor
    private func load() async -> ProgressEntry {
        let snapshot = await SnapshotLoader.load()
        let totals = (try? await HealthKitService().dailyEnergyTotals()) ?? []
        let earned = StreakCalendar.earnedDays(
            totals: totals,
            targetDeficitKcal: snapshot.deficitTargetKcal,
            targetsByDay: DeficitTargetHistory.targetsByDay(),
            untrackedBelowKcal: SharedStore.untrackedBelowKcal
        )
        return ProgressEntry(
            date: .now,
            snapshot: snapshot,
            streak: StreakCalendar.currentStreak(earned: earned)
        )
    }
}

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnigiriProgress", provider: ProgressProvider()) { entry in
            ProgressWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Progress")
        .description("Gauge, sodium, water, and streak in one card.")
        .supportedFamilies([.systemMedium])
    }
}

/// The meter widget's stat-first sibling: no buttons, one glance —
/// gauge + headline on the left, sodium/water/streak on the right.
struct ProgressWidgetView: View {
    let entry: ProgressEntry

    private var summary: DailyEnergySummary { entry.snapshot.summary }

    var body: some View {
        if entry.snapshot.needsSetup {
            VStack(spacing: 6) {
                OnigiriGauge(progress: 0)
                    .frame(width: 44, height: 44)
                Text("Open Onigiri to set up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 14) {
                VStack(spacing: 4) {
                    OnigiriGauge(progress: entry.snapshot.gaugeProgress)
                        .frame(width: 56, height: 56)
                    if SharedStore.showsRemainingKcal, let remaining = entry.snapshot.remainingKcal {
                        let headline = CalorieBudget.remainingHeadline(remaining)
                        Text(headline.value, format: .number.precision(.fractionLength(0)))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.remainingStatus(kcal: remaining))
                        Text(headline.caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(summary.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(summary.balanceKcal <= 0 ? Color.green : Color.orange)
                        Text("kcal balance")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    statLine("🧂",
                             "\(summary.sodiumMg.formatted(.number.precision(.fractionLength(0)))) mg",
                             color: Color.sodiumStatus(mg: summary.sodiumMg, limitMg: SharedStore.sodiumLimitMg))
                    statLine("💧",
                             "\(summary.waterOz.formatted(.number.precision(.fractionLength(0)))) / \(entry.snapshot.waterGoalOz.formatted(.number.precision(.fractionLength(0)))) oz",
                             color: summary.waterOz >= entry.snapshot.waterGoalOz ? .green : .secondary)
                    statLine(SharedStore.rewardEmoji,
                             entry.streak == 1 ? "1 day streak" : "\(entry.streak) day streak",
                             color: entry.streak > 0 ? .green : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statLine(_ icon: String, _ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(icon)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}
