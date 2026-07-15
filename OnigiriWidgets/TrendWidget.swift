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
        let needsSetup = await PlanCache.needsSetup()
        let points = (try? await HealthKitService().bodyMassHistory(days: 90)) ?? []
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
                .containerBackground(Color.riceCanvas, for: .widget)
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
            // One spoken sentence — the marks are unlabeled points.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weight trend chart")
            .accessibilityValue(chartSummary)
        }
    }

    private var chartSummary: String {
        var parts: [String] = []
        if let latest = entry.smoothed.last?.weightLb {
            parts.append("7-day average \(latest.formatted(.number.precision(.fractionLength(1)))) pounds")
        }
        if let target = entry.targetLb {
            parts.append("target \(target.formatted(.number.precision(.fractionLength(0)))) pounds")
        }
        return parts.isEmpty ? "No weigh-ins yet" : parts.joined(separator: ", ")
    }

    private var yDomain: ClosedRange<Double> {
        let weights = entry.points.map(\.weightLb) + [entry.targetLb].compactMap(\.self)
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        return (min - 2)...(max + 2)
    }
}
