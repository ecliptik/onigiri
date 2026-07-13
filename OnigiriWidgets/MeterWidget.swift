import WidgetKit
import SwiftUI
import OnigiriKit

/// Medium home-screen widget: balance, gauge progress, water, and
/// interactive quick-log buttons for water and a configured meal.
struct MeterWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "OnigiriMeter",
            intent: MeterWidgetConfiguration.self,
            provider: MeterProvider()
        ) { entry in
            MeterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Calorie Meter")
        .description("Today's balance and goal progress, with one-tap logging.")
        .supportedFamilies([.systemMedium])
    }
}

struct MeterEntry: TimelineEntry {
    let date: Date
    let snapshot: DaySnapshot
    let meal: MealEntity?
}

struct MeterProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MeterEntry {
        MeterEntry(date: .now, snapshot: .placeholder, meal: nil)
    }

    func snapshot(for configuration: MeterWidgetConfiguration, in context: Context) async -> MeterEntry {
        // The gallery gets the flattering placeholder, not a fresh
        // install's zeros (or a watchdog fallback from a slow query).
        if context.isPreview {
            return MeterEntry(date: .now, snapshot: .placeholder, meal: configuration.meal)
        }
        return MeterEntry(date: .now, snapshot: await SnapshotLoader.load(), meal: configuration.meal)
    }

    func timeline(for configuration: MeterWidgetConfiguration, in context: Context) async -> Timeline<MeterEntry> {
        let now = Date()
        let snapshot = await SnapshotLoader.load()
        let refresh = now.addingTimeInterval(30 * 60)
        if let midnight = nextMidnight(after: now), midnight <= refresh {
            return Timeline(
                entries: [
                    MeterEntry(date: now, snapshot: snapshot, meal: configuration.meal),
                    MeterEntry(date: midnight, snapshot: snapshot.newDay, meal: configuration.meal),
                ],
                policy: .after(midnight)
            )
        }
        return Timeline(
            entries: [MeterEntry(date: now, snapshot: snapshot, meal: configuration.meal)],
            policy: .after(refresh)
        )
    }
}

struct MeterWidgetView: View {
    let entry: MeterEntry

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
            meter
        }
    }

    private var meter: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Honor the same "Calorie display" setting as the app/watch.
                if SharedStore.showsRemainingKcal, let remaining = entry.snapshot.remainingKcal {
                    let headline = CalorieBudget.remainingHeadline(remaining)
                    Text(headline.value, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.remainingStatus(kcal: remaining))
                        .minimumScaleFactor(0.6)
                        .invalidatableContent()
                    Text(headline.caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(summary.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(summary.balanceKcal <= 0 ? Color.green : Color.orange)
                        .minimumScaleFactor(0.6)
                        .invalidatableContent()
                    Text("kcal balance")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    OnigiriGauge(progress: entry.snapshot.gaugeProgress)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        if entry.snapshot.deficitTargetKcal != nil {
                            Text("\(Int(entry.snapshot.gaugeProgress * 100))% of goal")
                                .font(.caption2.weight(.medium))
                        }
                        Text("\(summary.waterOz, format: .number.precision(.fractionLength(0)))/\(entry.snapshot.waterGoalOz, format: .number.precision(.fractionLength(0))) oz")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .invalidatableContent()
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button(intent: LogWaterIntent()) {
                    Label(
                        "\(SharedStore.waterServingOz, format: .number.precision(.fractionLength(0))) oz",
                        systemImage: "drop.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                if let meal = entry.meal {
                    Button(intent: LogMealIntent(meal: meal)) {
                        Label(meal.name, systemImage: "fork.knife")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    Text("Edit widget to pick a meal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 118)
        }
    }
}
