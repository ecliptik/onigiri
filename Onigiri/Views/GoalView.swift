import SwiftUI
import SwiftData
import Charts
import OnigiriKit

/// Set the weight goal: target weight + date. Shows the computed daily
/// deficit and calorie budget with safety guardrails.
struct GoalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var goals: [GoalSettings]

    @State private var targetWeightLb: Double?
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
    @State private var mode: String = GoalMode.lose
    @State private var manualWeightLb: Double?
    @State private var healthWeightLb: Double?
    @State private var averageBurnKcal: Double?
    @State private var weightHistory: [WeightTrend.Point] = []
    @State private var dailyTotals: [DayEnergyTotals] = []
    /// Cached 7-day smoothing of weightHistory (see .task).
    @State private var smoothedHistory: [WeightTrend.Point] = []
    /// The chart's derived numbers, cached like the smoothing: as
    /// computed properties they re-derived (least-squares included) on
    /// every body evaluation, and the tab-bar pin's scroll-state write
    /// re-renders this screen mid-scroll — the Goal scroll "stick".
    @State private var projectedDate: Date?
    @State private var chartYDomain: ClosedRange<Double> = 0...1
    @State private var predicted30Lb: Double?
    @State private var actual30Lb: Double?
    /// Staleness stamp for the .task reads (see .task).
    @State private var lastLoaded: Date?
    @State private var loaded = false
    @State private var confirmingGoalRemoval = false
    @FocusState private var weightFieldFocused: Bool

    private let health = HealthKitService()

    private var currentWeightLb: Double? { healthWeightLb ?? manualWeightLb }

    private var isMaintenance: Bool { mode == GoalMode.maintain }

    private var validation: GoalUpsert.Validation {
        GoalUpsert.validate(targetLb: targetWeightLb, currentLb: currentWeightLb, mode: mode)
    }

    /// Save enables only when the form is valid AND differs from the
    /// stored goal — the tab has no Cancel, so an always-on Save would
    /// invite no-ops, and an invalid save used to slip through silently.
    private var isDirty: Bool {
        guard validation == .valid else { return false }
        guard let goal = goals.first else { return true }
        if (goal.mode ?? GoalMode.lose) != mode { return true }
        // In maintenance the target knobs are hidden — their staleness
        // isn't a difference the user can see or intend.
        if isMaintenance { return false }
        return goal.targetWeightLb != targetWeightLb
            || !Calendar.current.isDate(goal.targetDate, inSameDayAs: targetDate)
            || (healthWeightLb == nil && goal.fallbackCurrentWeightLb != manualWeightLb)
    }

    private var plan: CalorieBudget.Plan? {
        if isMaintenance {
            return CalorieBudget.maintenancePlan(averageDailyBurn: averageBurnKcal ?? 2000)
        }
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
                // Mode first (the user: the Lose/Maintain choice tops the
                // screen), then the trend chart, then the knobs.
                Section {
                    // Segmented controls ignore Dynamic Type — go menu at
                    // accessibility sizes so the mode names scale too
                    // (the ScopeBar/PortionSheet rule; this picker was
                    // the one holdout).
                    if dynamicTypeSize.isAccessibilitySize {
                        Picker("Goal", selection: $mode) {
                            Text("Lose Weight").tag(GoalMode.lose)
                            Text("Maintain").tag(GoalMode.maintain)
                        }
                        .pickerStyle(.menu)
                    } else {
                        Picker("Goal", selection: $mode) {
                            Text("Lose Weight").tag(GoalMode.lose)
                            Text("Maintain").tag(GoalMode.maintain)
                        }
                        .pickerStyle(.segmented)
                    }
                } footer: {
                    if isMaintenance {
                        Text("To hold steady, eat within your average daily burn. Any deficit earns the day's badge.")
                    }
                }

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
                        Text("No weight in Apple Health yet — enter it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isMaintenance {
                    Section("Target") {
                    LabeledContent("Weight (lb)") {
                        TextField("0", value: $targetWeightLb, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($weightFieldFocused)
                    }
                    DatePicker("By date", selection: $targetDate, in: Date.now..., displayedComponents: .date)
                    // Say WHY the plan is missing and Save is disabled —
                    // it used to just silently vanish.
                    if validation == .targetNotBelowCurrent {
                        Text("Target must be below your current weight.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if targetWeightLb == nil {
                        Text("Enter a target weight to set a goal.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    }
                }

                if let plan {
                    Section("Daily plan") {
                        if !isMaintenance, let current = currentWeightLb, let target = targetWeightLb {
                            LabeledContent("To lose") {
                                Text("\(current - target, format: .number.precision(.fractionLength(1))) lb")
                            }
                            LabeledContent("Deficit needed") {
                                Text("\(plan.requiredDailyDeficit, format: .number.precision(.fractionLength(0))) kcal/day")
                            }
                        }
                        LabeledContent("Calorie budget") {
                            Text("≈ \(plan.dailyBudget, format: .number.precision(.fractionLength(0))) kcal/day")
                        }
                        LabeledContent("Average burn") {
                            // The fallback used to present as fact — the
                            // whole budget inherits this guess.
                            Text(averageBurnKcal.map {
                                "≈ \($0.formatted(.number.precision(.fractionLength(0)))) kcal/day"
                            } ?? "≈ 2000 kcal/day (assumed)")
                        }
                        if averageBurnKcal == nil {
                            Text("No activity data in Health yet — the plan assumes 2000 kcal/day until burn history exists.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

                // Goals used to be edit-only: hitting the target (or
                // quitting the diet) left the deficit budget and streak
                // judging on forever.
                if !goals.isEmpty {
                    Section {
                        Button("Remove Goal", role: .destructive) {
                            confirmingGoalRemoval = true
                        }
                    } footer: {
                        Text("If no goal is set, any deficit earns a daily badge.")
                    }
                }
            }
            .alert("Remove your goal?", isPresented: $confirmingGoalRemoval) {
                Button("Remove", role: .destructive) { removeGoal() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The deficit target and daily budget go away. Your logs aren't touched.")
            }
            .compactSections()
            .readableContentWidth(groupedBackground: true)
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
                // reliably render on iOS 26, so this lives in the nav bar —
                // .principal, matching the food form's.)
                if weightFieldFocused {
                    ToolbarItem(placement: .principal) {
                        Button {
                            weightFieldFocused = false
                        } label: {
                            Text("Done")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.onRicePaper)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.ricePaper)
                    }
                }
            }
        }
        .task {
            // TabView re-runs this on every visit; a quick tab bounce
            // shouldn't replay four HealthKit reads over 90-day windows
            // (TodayModel's staleness rule). Day-roll still refreshes.
            if let last = lastLoaded,
               Date.now.timeIntervalSince(last) < 30,
               Calendar.current.isDate(last, inSameDayAs: .now) {
            } else {
                // Independent reads — concurrent, not serial (the trend
                // chart used to populate a query-chain late).
                async let weightRead = health.latestBodyMassLb()
                async let burnRead = health.averageDailyBurnKcal()
                async let historyRead = health.bodyMassHistory()
                async let totalsRead = health.dailyEnergyTotals()
                healthWeightLb = (try? await weightRead) ?? nil
                averageBurnKcal = (try? await burnRead) ?? nil
                weightHistory = (try? await historyRead) ?? []
                dailyTotals = (try? await totalsRead) ?? []
                // Smooth once per load, not per keystroke: typing a target
                // weight re-evaluates body per digit, and each evaluation
                // re-averaged ~90 points and re-fit the slope.
                smoothedHistory = WeightTrend.movingAverage(weightHistory, windowDays: 7)
                lastLoaded = .now
            }
            if !loaded, let goal = goals.first {
                targetWeightLb = goal.targetWeightLb
                targetDate = goal.targetDate
                manualWeightLb = goal.fallbackCurrentWeightLb
                mode = goal.mode ?? GoalMode.lose
                loaded = true
            }
            deriveTrendStats()
        }
        .onChange(of: targetWeightLb) { deriveTrendStats() }
        .onChange(of: mode) { deriveTrendStats() }
    }

    // MARK: - Predicted vs actual (trailing 30 days)

    /// Recompute the cached chart stats (see the @State block above).
    /// Called when the HealthKit reads land and when the target or
    /// mode edits change what the chart derives from.
    private func deriveTrendStats() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        // Nil until the window has logged days — no data, no claim.
        let deficits = dailyTotals
            .filter { $0.day >= thirtyDaysAgo }
            .map(\.deficitKcal)
        predicted30Lb = deficits.isEmpty
            ? nil
            : WeightTrend.Change.predictedLb(totalDeficitKcal: deficits.reduce(0, +))
        actual30Lb = WeightTrend.Change.actualLb(history: weightHistory, from: thirtyDaysAgo, to: .now)

        // Projected date of reaching the target at the recent trend,
        // from the least-squares slope of the last three weeks of
        // smoothed weigh-ins.
        projectedDate = nil
        if let target = targetWeightLb,
           let current = smoothedHistory.last?.weightLb,
           current > target,
           let slope = WeightTrend.slopeLbPerDay(smoothedHistory.suffix(21).map { $0 }),
           slope < -0.01 {
            let days = (current - target) / -slope
            if days < 365 * 3 {
                projectedDate = Calendar.current.date(byAdding: .day, value: Int(days.rounded(.up)), to: .now)
            }
        }

        let weights = weightHistory.map(\.weightLb)
            + (isMaintenance ? [] : [targetWeightLb].compactMap(\.self))
        if let lo = weights.min(), let hi = weights.max() {
            chartYDomain = (lo - 2)...(hi + 2)
        } else {
            chartYDomain = 0...1
        }
    }

    private func signedLb(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))) lb"
    }

    // MARK: - Weight trend


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
                    if !isMaintenance, let target = targetWeightLb {
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

                if isMaintenance {
                    // No target line in maintenance — the chart is just
                    // the scale holding (or not).
                    EmptyView()
                } else if let projectedDate {
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

    private func save() {
        guard validation == .valid else { return }
        // targetWeightLb is non-optional on the model; in maintenance
        // it's ignored, so park the best-known weight there.
        guard let target = targetWeightLb
            ?? (isMaintenance ? (currentWeightLb ?? goals.first?.targetWeightLb ?? 0) : nil)
        else { return }
        GoalUpsert.save(
            targetLb: target,
            targetDate: targetDate,
            healthWeightLb: healthWeightLb,
            manualWeightLb: manualWeightLb,
            mode: mode == GoalMode.lose ? nil : mode,
            goals: goals,
            context: context
        )
        weightFieldFocused = false
        ToastCenter.shared.show("Goal saved ✓")
    }

    private func removeGoal() {
        goals.forEach(context.delete)
        targetWeightLb = nil
        mode = GoalMode.lose
        weightFieldFocused = false
        // push sends GoalUpdate.clear to the watch and reloads widgets.
        PhoneSyncService.shared.push(from: context)
        ReminderScheduler.shared.replan()
        ToastCenter.shared.show("Goal removed ✓")
    }
}
