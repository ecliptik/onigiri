import SwiftUI
import SwiftData
import Charts
import OnigiriKit

/// Set the weight goal: target weight + date. Shows the computed daily
/// deficit and calorie budget with safety guardrails.
struct GoalView: View {
    @Environment(\.modelContext) private var context
    @Query private var goals: [GoalSettings]

    @State private var targetWeightLb: Double?
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
    @State private var manualWeightLb: Double?
    @State private var healthWeightLb: Double?
    @State private var averageBurnKcal: Double?
    @State private var weightHistory: [WeightTrend.Point] = []
    @State private var dailyTotals: [DayEnergyTotals] = []
    @State private var loaded = false
    @FocusState private var weightFieldFocused: Bool

    private let health = HealthKitService()

    private var currentWeightLb: Double? { healthWeightLb ?? manualWeightLb }

    /// Save enables only when the form differs from the stored goal —
    /// the tab has no Cancel, so an always-on Save would invite no-ops.
    private var isDirty: Bool {
        guard targetWeightLb != nil, currentWeightLb != nil else { return false }
        guard let goal = goals.first else { return true }
        return goal.targetWeightLb != targetWeightLb
            || !Calendar.current.isDate(goal.targetDate, inSameDayAs: targetDate)
            || (healthWeightLb == nil && goal.fallbackCurrentWeightLb != manualWeightLb)
    }

    private var plan: CalorieBudget.Plan? {
        guard let current = currentWeightLb, let target = targetWeightLb, target < current else { return nil }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: .now), to: targetDate
        ).day ?? 0
        return CalorieBudget.plan(
            currentWeightLb: current,
            targetWeightLb: target,
            daysRemaining: days,
            averageDailyBurn: averageBurnKcal ?? 2000
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // The trend leads: where you ARE against the goal is the
                // screen's headline; the knobs to change it come after.
                trendSection

                Section("Current weight") {
                    if let healthWeightLb {
                        LabeledContent("From Apple Health") {
                            Text("\(healthWeightLb, format: .number.precision(.fractionLength(1))) lb")
                        }
                    } else {
                        LabeledContent("Weight (lb)") {
                            TextField("0", value: $manualWeightLb, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($weightFieldFocused)
                        }
                        Text("No weight in Apple Health yet — step on your scale, or enter it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Target") {
                    LabeledContent("Weight (lb)") {
                        TextField("0", value: $targetWeightLb, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($weightFieldFocused)
                    }
                    DatePicker("By date", selection: $targetDate, in: Date.now..., displayedComponents: .date)
                }

                if let plan, let current = currentWeightLb, let target = targetWeightLb {
                    Section("Daily plan") {
                        LabeledContent("To lose") {
                            Text("\(current - target, format: .number.precision(.fractionLength(1))) lb")
                        }
                        LabeledContent("Deficit needed") {
                            Text("\(plan.requiredDailyDeficit, format: .number.precision(.fractionLength(0))) kcal/day")
                        }
                        LabeledContent("Calorie budget") {
                            Text("≈ \(plan.dailyBudget, format: .number.precision(.fractionLength(0))) kcal/day")
                        }
                        LabeledContent("Average burn") {
                            Text("≈ \(averageBurnKcal ?? 2000, format: .number.precision(.fractionLength(0))) kcal/day")
                        }
                        // Is the math showing up on the scale? Trailing 30
                        // days of deficit vs the smoothed weigh-in change.
                        if let predicted = predicted30Lb, let actual = actual30Lb {
                            LabeledContent("Last 30 days") {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("≈ \(signedLb(predicted)) predicted")
                                    Text("\(signedLb(actual)) on the scale")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if plan.isAggressive {
                            Label(
                                "That pace is aggressive. A later target date means a gentler daily budget.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .compactSections()
            .readableContentWidth()
            .expandsTabBarAtTop()
            .navigationTitle("Goal")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                // Confirm in the nav bar like every other form in the app.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isDirty)
                }
                // Decimal pads have no return key; surface a Done while
                // editing. (The keyboard-accessory toolbar placement doesn't
                // reliably render on iOS 26, so this lives in the nav bar.)
                if weightFieldFocused {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            weightFieldFocused = false
                        } label: {
                            Text("Done")
                                .fontWeight(.semibold)
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.ricePaper)
                    }
                }
            }
        }
        .task {
            healthWeightLb = (try? await health.latestBodyMassLb()) ?? nil
            averageBurnKcal = (try? await health.averageDailyBurnKcal()) ?? nil
            weightHistory = (try? await health.bodyMassHistory()) ?? []
            dailyTotals = (try? await health.dailyEnergyTotals()) ?? []
            if !loaded, let goal = goals.first {
                targetWeightLb = goal.targetWeightLb
                targetDate = goal.targetDate
                manualWeightLb = goal.fallbackCurrentWeightLb
                loaded = true
            }
        }
    }

    // MARK: - Predicted vs actual (trailing 30 days)

    private var thirtyDaysAgo: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    }

    /// Nil until the window has logged days — no data, no claim.
    private var predicted30Lb: Double? {
        let deficits = dailyTotals
            .filter { $0.day >= thirtyDaysAgo }
            .map(\.deficitKcal)
        guard !deficits.isEmpty else { return nil }
        return WeightTrend.Change.predictedLb(totalDeficitKcal: deficits.reduce(0, +))
    }

    private var actual30Lb: Double? {
        WeightTrend.Change.actualLb(history: weightHistory, from: thirtyDaysAgo, to: .now)
    }

    private func signedLb(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))) lb"
    }

    // MARK: - Weight trend

    private var smoothedHistory: [WeightTrend.Point] {
        WeightTrend.movingAverage(weightHistory, windowDays: 7)
    }

    /// Projected date of reaching the target at the recent trend, from the
    /// least-squares slope of the last three weeks of smoothed weigh-ins.
    private var projectedDate: Date? {
        guard let target = targetWeightLb,
              let current = smoothedHistory.last?.weightLb,
              current > target,
              let slope = WeightTrend.slopeLbPerDay(smoothedHistory.suffix(21).map { $0 }),
              slope < -0.01
        else { return nil }
        let days = (current - target) / -slope
        guard days < 365 * 3 else { return nil }
        return Calendar.current.date(byAdding: .day, value: Int(days.rounded(.up)), to: .now)
    }

    @ViewBuilder
    private var trendSection: some View {
        // No header: it leads the screen now, and the chart speaks for
        // itself.
        Section {
            if weightHistory.count >= 2 {
                Chart {
                    ForEach(Array(weightHistory.enumerated()), id: \.offset) { _, point in
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.weightLb)
                        )
                        .foregroundStyle(.secondary)
                        .opacity(0.35)
                        .symbolSize(20)
                    }
                    ForEach(Array(smoothedHistory.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("7-day average", point.weightLb)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    }
                    if let target = targetWeightLb {
                        RuleMark(y: .value("Target", target))
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .annotation(position: .bottom, alignment: .leading) {
                                Text("Target \(target, format: .number.precision(.fractionLength(0))) lb")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                    }
                }
                .chartYScale(domain: chartYDomain)
                .frame(height: 220)
                .padding(.vertical, 4)

                if let projectedDate {
                    Label {
                        Text("On this trend, you'll hit your target around \(projectedDate, format: .dateTime.month(.wide).day())")
                    } icon: {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .foregroundStyle(.green)
                    }
                    .font(.subheadline)
                } else if targetWeightLb != nil {
                    Text("No steady downward trend yet — projections appear once the 7-day average starts moving.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Weigh-ins from your scale will chart here once Apple Health has a few days of data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chartYDomain: ClosedRange<Double> {
        let weights = weightHistory.map(\.weightLb) + [targetWeightLb].compactMap(\.self)
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        return (min - 2)...(max + 2)
    }

    private func save() {
        guard let target = targetWeightLb else { return }
        if let goal = goals.first {
            goal.targetWeightLb = target
            goal.targetDate = targetDate
            goal.fallbackCurrentWeightLb = healthWeightLb == nil ? manualWeightLb : nil
        } else {
            context.insert(GoalSettings(
                targetWeightLb: target,
                targetDate: targetDate,
                fallbackCurrentWeightLb: healthWeightLb == nil ? manualWeightLb : nil
            ))
        }
        weightFieldFocused = false
        PhoneSyncService.shared.push(from: context)
        ToastCenter.shared.show("Goal saved ✓")
    }
}
