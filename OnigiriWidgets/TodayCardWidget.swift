import WidgetKit
import SwiftUI
import OnigiriKit

/// Large/medium home-screen widget: the top of Today, mirrored — the
/// kcal-left ring with Burned/Eaten flanking, the tracked-metric pills,
/// the rice-paper canvas — with ‹ › day paging, an in-place water
/// button, and a + that deep-links into the Log sheet for the shown day.
struct TodayCardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.todayCard, provider: TodayCardProvider()) { entry in
            TodayCardView(entry: entry)
                .containerBackground(Color.riceCanvas, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's balance, burned and eaten, and your tracked metrics.")
        .supportedFamilies([.systemLarge, .systemMedium])
    }
}

struct TodayCardEntry: TimelineEntry {
    let date: Date
    let snapshot: DaySnapshot
    /// The browsed day; nil renders today.
    var day: Date?
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
            // Push-based reloads keep widgets fresh; this poll is only a fallback.
            let refresh = now.addingTimeInterval(WidgetRefreshPolicy.pollFallback)
            let midnight = nextMidnight(after: now)
            if let day = TodayCardBrowse.shownDay(now: now),
               let browsed = await SnapshotLoader.load(day: day) {
                // Pre-render the snap-back: at midnight the browsed day
                // goes stale and the card shows the new (empty) today.
                if let midnight, midnight <= refresh {
                    let today = await SnapshotLoader.load()
                    completion(Timeline(
                        entries: [
                            TodayCardEntry(date: now, snapshot: browsed, day: day),
                            TodayCardEntry(date: midnight, snapshot: today.newDay),
                        ],
                        policy: .after(midnight)
                    ))
                } else {
                    completion(Timeline(
                        entries: [TodayCardEntry(date: now, snapshot: browsed, day: day)],
                        policy: .after(refresh)
                    ))
                }
                return
            }
            let snapshot = await SnapshotLoader.load()
            if let midnight, midnight <= refresh {
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
    @Environment(\.widgetFamily) private var family
    let entry: TodayCardEntry

    private var snapshot: DaySnapshot { entry.snapshot }
    private var summary: DailyEnergySummary { snapshot.summary }
    private var isLarge: Bool { family == .systemLarge }

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
        } else if isLarge {
            VStack(spacing: 10) {
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
                        // The flanks fit as one caption line beside the
                        // ring; full columns didn't.
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

    // MARK: - Header (paging + logging)

    private var dayTitle: String {
        guard let day = entry.day else { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// The shown day's Log-sheet deep link (backfill included — the
    /// sheet logs into the browsed day, like the app's day browsing).
    private var logURL: URL {
        var components = URLComponents()
        components.scheme = "onigiri"
        components.host = "log"
        if let day = entry.day {
            components.queryItems = [URLQueryItem(name: "day", value: Self.dayFormat.string(from: day))]
        }
        return components.url!
    }

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var atFloor: Bool {
        guard let floor = Calendar.current.date(
            byAdding: .day, value: -TodayCardBrowse.daysBack,
            to: Calendar.current.startOfDay(for: entry.date)
        ) else { return false }
        return (entry.day ?? Calendar.current.startOfDay(for: entry.date)) <= floor
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(intent: PageTodayCardIntent(delta: -1)) {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.riceToast)
                    .frame(width: 26, height: 26)
                    .background(.quaternary.opacity(0.5), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(atFloor)
            .accessibilityLabel("Previous day")

            Text(dayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 2)
                .invalidatableContent()

            Button(intent: PageTodayCardIntent(delta: 1)) {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.riceToast)
                    .frame(width: 26, height: 26)
                    .background(.quaternary.opacity(0.5), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(entry.day == nil)
            .accessibilityLabel("Next day")

            Spacer(minLength: 0)

            // In-place water: the same intent as Control Center, logging
            // the default serving to now (today) — no app launch.
            Button(intent: LogWaterIntent()) {
                Image(systemName: "drop.fill")
                    .font(.footnote)
                    .foregroundStyle(.blue)
                    .frame(width: 26, height: 26)
                    .background(.quaternary.opacity(0.5), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log water")

            // Into the app's Log sheet for the SHOWN day.
            Link(destination: logURL) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.onRicePaper)
                    .frame(width: 26, height: 26)
                    .background(Color.ricePaper, in: .circle)
            }
            .accessibilityLabel("Log food or meal")
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
                    .padding(isLarge ? 22 : 12)
            }
            // Fixed like Today's 190pt ring (scaled to the widget's
            // canvas) — an HStack-share ring drifted with flank width
            // and squeezed the headline into truncation.
            .frame(width: ringSize, height: ringSize)
            .accessibilityElement(children: .combine)
            .accessibilityValue("\((eaten * 100).formatted(.number.precision(.fractionLength(0)))) percent of \(entry.day == nil ? "today's" : "the day's") budget eaten")
        } else {
            headline
        }
    }

    private var ringSize: CGFloat { isLarge ? 168 : 104 }
    private var headlineSize: CGFloat { isLarge ? 44 : 26 }

    /// The headline number in the user's chosen style (same "Calorie
    /// display" setting as the app/watch).
    private var headline: some View {
        VStack(spacing: 2) {
            if SharedStore.showsRemainingKcal, let remaining = snapshot.remainingKcal {
                let headline = CalorieBudget.remainingHeadline(remaining)
                Text(headline.value, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Color.remainingStatus(kcal: remaining))
                    .invalidatableContent()
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
                    .invalidatableContent()
                Text("kcal balance")
                    .font(isLarge ? .caption : .caption2)
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

    /// The medium family's one-line flank: "1,505 Burned".
    private func miniFlank(_ value: Double, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .invalidatableContent()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    // MARK: - Tracked metrics

    /// The two configurable tracked-metric pills (sodium and water by
    /// default) — a slot set to None disappears; a lone survivor centers.
    /// Large lays them side by side, medium stacks them.
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
