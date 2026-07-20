import SwiftUI
import SwiftData
import Charts
import OnigiriKit

/// Set the weight goal: target weight + date. Shows the computed daily
/// deficit and calorie budget with safety guardrails.
struct GoalView: View {
    @Environment(\.modelContext) private var context
    /// The trend chart's height rides Dynamic Type so its axis labels
    /// keep room at accessibility sizes (the fixed 220 clipped them).
    @ScaledMetric(relativeTo: .body) private var chartHeight = 220.0
    @Query private var goals: [GoalSettings]

    @State private var targetWeightLb: Double?
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
    @State private var mode: String = GoalMode.lose
    @State private var manualWeightLb: Double?
    @State private var loaded = false
    @State private var confirmingGoalRemoval = false
    @FocusState private var weightFieldFocused: Bool

    /// HealthKit reads and derived chart stats live in the model (the
    /// TodayModel shape) — the view keeps only form state.
    @State private var model = GoalModel()

    private var currentWeightLb: Double? { model.healthWeightLb ?? manualWeightLb }

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
            || (model.healthWeightLb == nil && goal.fallbackCurrentWeightLb != manualWeightLb)
    }

    private var plan: CalorieBudget.Plan? {
        // The preview keeps GoalUpsert's target-below-current rule;
        // derivation itself is the shared kit path (clamped burn — this
        // preview used to lag Today on high-burn days by skipping the
        // today-actual floor).
        if !isMaintenance {
            guard let current = currentWeightLb, let target = targetWeightLb, target < current
            else { return nil }
        }
        return CalorieBudget.derivePlan(
            isMaintenance: isMaintenance,
            currentWeightLb: currentWeightLb,
            targetWeightLb: targetWeightLb,
            targetDate: targetDate,
            averageDailyBurnKcal: model.averageBurnKcal,
            todayActualBurnKcal: model.todayBurnKcal
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // Mode first (the user: the Lose/Maintain choice tops the
                // screen), then the trend chart, then the knobs.
                Section {
                    // The shared ScopeBar, floating on the canvas exactly
                    // like Foods' Favorites/Foods/Meals bar (the user:
                    // the card-wrapped picker read as a different
                    // control). ScopeBar owns the menu-at-AX-sizes rule.
                    ScopeBar(
                        options: [("Lose Weight", GoalMode.lose), ("Maintain", GoalMode.maintain)],
                        selection: $mode
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    if isMaintenance {
                        Text("To hold steady, eat within your average daily burn. Any deficit earns the day's badge.")
                    }
                }

                trendSection

                Section("Current weight") {
                    if let healthWeightLb = model.healthWeightLb {
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
                            Text(model.averageBurnKcal.map {
                                "≈ \($0.formatted(.number.precision(.fractionLength(0)))) kcal/day"
                            } ?? "≈ 2000 kcal/day (assumed)")
                        }
                        if model.averageBurnKcal == nil {
                            Text("No activity data in Health yet — the plan assumes 2000 kcal/day until burn history exists.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // Is the math showing up on the scale? Trailing 30
                        // days of deficit vs the smoothed weigh-in change.
                        if let predicted = model.trend.predicted30Lb, let actual = model.trend.actual30Lb {
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
            .navigationTitle("Goal")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                // Confirm in the nav bar like every other form in the app.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut("s", modifiers: .command)
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
            await model.loadIfStale()
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

    /// The chart stats derive from the model's Health data plus the
    /// form's live target/mode (kit math, unit-tested there).
    private func deriveTrendStats() {
        model.deriveTrendStats(targetWeightLb: targetWeightLb, isMaintenance: isMaintenance)
    }

    /// The chart's one-sentence VoiceOver reading.
    private var chartSummary: String {
        var parts: [String] = []
        if let latest = model.smoothedHistory.last?.weightLb {
            parts.append("7-day average \(latest.formatted(.number.precision(.fractionLength(1)))) pounds")
        }
        if !isMaintenance, let target = targetWeightLb {
            parts.append("target \(target.formatted(.number.precision(.fractionLength(0)))) pounds")
        }
        return parts.isEmpty ? "No weigh-ins yet" : parts.joined(separator: ", ")
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
            if model.weightHistory.count >= 2 {
                Chart {
                    ForEach(Array(model.weightHistory.enumerated()), id: \.offset) { _, point in
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.weightLb)
                        )
                        .foregroundStyle(.secondary)
                        .opacity(0.35)
                        .symbolSize(20)
                    }
                    ForEach(Array(model.smoothedHistory.enumerated()), id: \.offset) { _, point in
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
                .chartYScale(domain: model.trend.chartYDomain)
                // One spoken sentence, not ~90 unlabeled point stops.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weight trend chart")
                .accessibilityValue(chartSummary)
                .frame(height: chartHeight)
                .padding(.vertical, 4)

                if isMaintenance {
                    // No target line in maintenance — the chart is just
                    // the scale holding (or not).
                    EmptyView()
                } else if let projectedDate = model.trend.projectedDate {
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
            healthWeightLb: model.healthWeightLb,
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
