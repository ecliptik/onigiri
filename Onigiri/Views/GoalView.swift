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
    /// Which weight field is editing — an enum (not a Bool) so moving
    /// directly between the two fields still fires the select-all
    /// onChange below.
    private enum WeightField: Hashable { case target, current, customBurn }
    @FocusState private var focusedField: WeightField?

    /// How the day's budget behaves — the answer that used to be baked
    /// into the math (2026-07-30). Defaults to the previous behavior, so
    /// an untouched install changes nothing.
    @AppStorage(SharedStore.budgetStyleKey, store: SharedStore.defaults)
    private var budgetStyle = BudgetStyle.automatic.rawValue
    @AppStorage(SharedStore.customExpectedBurnKey, store: SharedStore.defaults)
    private var customExpectedBurnRaw = 0.0
    @AppStorage(SharedStore.activityLevelKey, store: SharedStore.defaults)
    private var activityLevel = ActivityLevel.light.rawValue

    private var style: BudgetStyle { BudgetStyle.resolve(budgetStyle) }

    /// The stored double as an optional, so an unset custom burn shows a
    /// placeholder instead of a misleading 0.
    private var customExpectedBurn: Binding<Double?> {
        Binding(
            get: { customExpectedBurnRaw > 0 ? customExpectedBurnRaw : nil },
            set: { customExpectedBurnRaw = $0 ?? 0 }
        )
    }

    /// HealthKit reads and derived chart stats live in the model (the
    /// TodayModel shape) — the view keeps only form state.
    @State private var model = GoalModel()

    /// Display unit only: all state, validation, and saves stay lb.
    @AppStorage(SharedStore.weightUnitKey, store: SharedStore.defaults)
    private var weightUnitRaw = SharedStore.unitAutomatic
    private var unit: WeightUnit { WeightUnit.resolve(weightUnitRaw) }
    /// Whole pounds read fine; kg wants a decimal (1 kg ≈ 2.2 lb) — the
    /// target/anchor lines follow this where lb kept 0 digits.
    private var targetDigits: Int { unit == .pounds ? 0 : 1 }

    /// Entry proxy: shows (and accepts) the display unit, stores lb.
    /// The shown value rounds to 0.1 so a kg reopen reads "81.6", not
    /// the conversion's full tail.
    private func displayBinding(_ source: Binding<Double?>) -> Binding<Double?> {
        Binding(
            get: { source.wrappedValue.map { (unit.fromLb($0) * 10).rounded() / 10 } },
            set: { source.wrappedValue = $0.map(unit.toLb) }
        )
    }

    private var currentWeightLb: Double? { model.healthWeightLb ?? manualWeightLb }

    private var isMaintenance: Bool { mode == GoalMode.maintain }

    /// Two weigh-ins is the least that draws a line.
    private var hasChart: Bool { model.weightHistory.count >= 2 }

    /// Start → now → target, against the LIVE target field so an edited
    /// goal previews its own bar. The start is the stored stamp, or the
    /// earliest weigh-in on record for goals set before the stamp
    /// existed (kit rules, tested there). Milestones step in the display
    /// unit's round number — 5 lb, or 2 kg.
    private var progress: GoalProgress? {
        GoalProgress.resolve(
            startWeightLb: goals.first?.startWeightLb,
            startedAt: goals.first?.startedAt,
            weightHistory: model.weightHistory,
            currentWeightLb: currentWeightLb,
            targetWeightLb: targetWeightLb,
            isMaintenance: isMaintenance,
            milestoneStepLb: GoalProgress.milestoneStepLb(for: unit)
        )
    }

    /// The mark being worked toward — the only one the chart labels.
    private var nextMilestone: GoalProgress.Milestone? {
        progress?.milestones.first { !$0.isReached }
    }

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
        if isMaintenance {
            // The hold-near anchor is maintenance's one knob; an empty
            // field means "keep the stored anchor", not a change.
            return targetWeightLb.map { $0 != goal.targetWeightLb } ?? false
        }
        return goal.targetWeightLb != targetWeightLb
            || !Calendar.current.isDate(goal.targetDate, inSameDayAs: targetDate)
            || (model.healthWeightLb == nil && goal.fallbackCurrentWeightLb != manualWeightLb)
    }

    /// The form differs from the stored goal at all, validity aside —
    /// isDirty gates Save, but Cancel must appear even for edits Save
    /// would refuse (an over-current target, a cleared field).
    private var hasEdits: Bool {
        guard let goal = goals.first else {
            return targetWeightLb != nil || manualWeightLb != nil || mode != GoalMode.lose
        }
        if (goal.mode ?? GoalMode.lose) != mode { return true }
        let storedTarget: Double? = goal.targetWeightLb > 0 ? goal.targetWeightLb : nil
        if isMaintenance {
            return targetWeightLb.map { $0 != storedTarget } ?? false
        }
        return storedTarget != targetWeightLb
            || !Calendar.current.isDate(goal.targetDate, inSameDayAs: targetDate)
            || (model.healthWeightLb == nil && goal.fallbackCurrentWeightLb != manualWeightLb)
    }

    /// The saved lose goal is met: the scale reached the stored target,
    /// and the form still shows that target (editing the field into
    /// invalidity keeps the plain warning instead of the celebration).
    private var goalReached: Bool {
        guard !isMaintenance, let goal = goals.first,
              (goal.mode ?? GoalMode.lose) == GoalMode.lose,
              let current = currentWeightLb,
              targetWeightLb == goal.targetWeightLb
        else { return false }
        return current <= goal.targetWeightLb
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
            todayActualBurnKcal: TodayBurnFloor.ratcheted(model.todayBurnKcal)
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
                        Text("To hold steady, eat close to your average daily burn. Landing within \(StreakCalendar.maintenanceBandKcal, format: .number.precision(.fractionLength(0))) kcal of even earns the day's badge.")
                    }
                }

                trendSection

                Section("Current weight") {
                    if let healthWeightLb = model.healthWeightLb {
                        LabeledContent("From Apple Health") {
                            Text("\(unit.fromLb(healthWeightLb), format: .number.precision(.fractionLength(1))) \(unit.symbol)")
                        }
                    } else {
                        LabeledContent("Weight (\(unit.symbol))") {
                            TextField("0", value: displayBinding($manualWeightLb), format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedField, equals: .current)
                        }
                        Text("No weight in Apple Health yet — enter it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isMaintenance {
                    targetSection
                } else {
                    holdNearSection
                }

                if let plan {
                    Section("Daily plan") {
                        if !isMaintenance, let current = currentWeightLb, let target = targetWeightLb {
                            LabeledContent("To lose") {
                                Text("\(unit.fromLb(current - target), format: .number.precision(.fractionLength(1))) \(unit.symbol)")
                            }
                            LabeledContent("Deficit needed") {
                                Text("\(plan.requiredDailyDeficit, format: .number.precision(.fractionLength(0))) kcal/day")
                            }
                        }
                        LabeledContent("Calorie budget") {
                            Text("≈ \(plan.dailyBudget, format: .number.precision(.fractionLength(0))) kcal/day")
                        }
                        // What the effort adds up to, independent of what
                        // the scale did this morning — the number a bad
                        // weigh-in can't take away (the user wanted
                        // something motivating that doesn't swing).
                        if model.trend.bankedLb > 0 {
                            LabeledContent("Banked so far") {
                                Text("\(model.trend.bankedKcal, format: .number.precision(.fractionLength(0))) kcal ≈ \(unit.fromLb(model.trend.bankedLb), format: .number.precision(.fractionLength(1))) \(unit.symbol)")
                                    .monospacedDigit()
                            }
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

                // Its OWN section, deliberately outside `if let plan`:
                // these two SHAPE the plan, so they have to stay
                // reachable when the plan can't be computed — goal
                // reached, target cleared, custom burn left blank.
                // Otherwise the knob that fixes it disappears exactly
                // when it's needed.
                Section("Calorie budget") {
                    // ONE choice, segmented so both options are visible at
                    // once — the two pickers this replaced ("expected
                    // burn" and "active days") were never really
                    // independent (the user, 2026-07-30).
                    Picker("Budget", selection: $budgetStyle) {
                        ForEach(BudgetStyle.allCases, id: \.rawValue) { style in
                            Text(style.label).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    // What the selected one actually does, in a sentence.
                    Text(style.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if style == .fixed {
                        // Optional under Fixed: pin the number, or leave
                        // it blank and keep using your own average.
                        LabeledContent("Burn per day") {
                            TextField(
                                model.averageBurnKcal.map {
                                    $0.formatted(.number.precision(.fractionLength(0)))
                                } ?? "2000",
                                value: customExpectedBurn, format: .number
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .customBurn)
                        }
                        // How much of a typical week is spent moving. Asked
                        // rather than measured on purpose: it describes the
                        // routine, which is what a steady number wants.
                        Picker("Activity level", selection: $activityLevel) {
                            ForEach(ActivityLevel.allCases, id: \.rawValue) { level in
                                Text(level.label).tag(level.rawValue)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        Text(ActivityLevel.resolve(activityLevel).detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // One tap to fill the field from the body Health
                        // already knows, instead of inventing a number.
                        if let suggestion = model.suggestedDailyBurnKcal {
                            Button {
                                customExpectedBurnRaw = suggestion
                                focusedField = nil
                            } label: {
                                HStack {
                                    Text("Use estimate")
                                    Spacer()
                                    Text("≈ \(suggestion, format: .number.precision(.fractionLength(0))) kcal/day")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .disabled(customExpectedBurnRaw == suggestion)
                        } else {
                            Text("Add your height and date of birth in Health for an estimate.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if customExpectedBurnRaw <= 0 {
                            Text("Leave blank to hold your recent average steady instead.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
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
                // Cancel ↔ Save, the same pair as every sheet — the
                // styled principal "Done" read as belonging to nothing.
                // Cancel appears once there's anything to back out of
                // (edits, valid or not, or an open keyboard) and
                // DISCARDS: it restores the stored goal and drops the
                // keyboard. Keeping edits while closing the keyboard is
                // the scroll (interactive dismiss) or Save.
                if hasEdits || focusedField != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { revertEdits() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!isDirty)
                }
            }
        }
        .task {
            await model.loadIfStale()
            if !loaded, goals.first != nil {
                applyStoredGoal()
                loaded = true
            }
            deriveTrendStats()
        }
        .onChange(of: focusedField) {
            // A tapped weight field starts with its value selected, so
            // typing replaces instead of appending. sendAction targets
            // the first responder — exactly the freshly-focused field —
            // one runloop later, once UIKit has installed it.
            guard focusedField != nil else { return }
            DispatchQueue.main.async {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil
                )
            }
        }
        // A weigh-in recorded elsewhere while this tab is up — the chart
        // is built entirely from samples this app never writes, so
        // without this it sat on the numbers it loaded on arrival.
        .onChange(of: ToastCenter.shared.weightWriteVersion) { _, _ in
            Task {
                await model.reload()
                deriveTrendStats()
            }
        }
        .onChange(of: targetWeightLb) { deriveTrendStats() }
        .onChange(of: mode) {
            // First switch into Maintain offers the current weight as
            // the hold-near anchor; a parked lose target, if any, wins.
            if isMaintenance, targetWeightLb == nil {
                targetWeightLb = currentWeightLb
            }
            deriveTrendStats()
        }
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
            parts.append("7-day average \(unit.fromLb(latest).formatted(.number.precision(.fractionLength(1)))) \(unit.spoken)")
        }
        if !isMaintenance, let target = targetWeightLb {
            parts.append("target \(unit.fromLb(target).formatted(.number.precision(.fractionLength(targetDigits)))) \(unit.spoken)")
        }
        // The milestone rungs are drawn, so they have to be spoken —
        // the one being worked toward is the one that means anything.
        if let next = nextMilestone {
            parts.append("next milestone \(unit.fromLb(next.lostLb).formatted(.number.precision(.fractionLength(0...1)))) \(unit.spoken) down")
        }
        return parts.isEmpty ? "No weigh-ins yet" : parts.joined(separator: ", ")
    }

    private func signedLb(_ value: Double) -> String {
        "\(unit.fromLb(value).formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))) \(unit.symbol)"
    }

    // MARK: - Target / hold-near

    /// The weight field both modes share (lose target / hold-near anchor).
    private var targetWeightField: some View {
        LabeledContent("Weight (\(unit.symbol))") {
            TextField("0", value: displayBinding($targetWeightLb), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .target)
        }
    }

    private var targetSection: some View {
        Section("Target") {
            targetWeightField
            DatePicker("By date", selection: $targetDate, in: Date.now..., displayedComponents: .date)
            // Reaching the target is a milestone, not a form error —
            // celebrate and offer the mode that fits now.
            if goalReached {
                Label {
                    Text("You've reached your target — nice work.")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                .font(.subheadline)
                Button("Switch to Maintain") {
                    mode = GoalMode.maintain
                    save()
                }
            // Say WHY the plan is missing and Save is disabled —
            // it used to just silently vanish.
            } else if validation == .targetNotBelowCurrent {
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

    private var holdNearSection: some View {
        Section {
            targetWeightField
        } header: {
            Text("Hold near")
        } footer: {
            Text("The chart's reference line. The badge judges eating within your burn, not the scale.")
        }
    }

    // MARK: - Weight trend


    @ViewBuilder
    private var trendSection: some View {
        // No header: it leads the screen now, and the chart speaks for
        // itself.
        Section {
            if hasChart {
                // Plotted in the display unit (not just relabeled) so
                // the y-axis ticks read as real kg/lb values.
                Chart {
                    ForEach(Array(model.weightHistory.enumerated()), id: \.offset) { _, point in
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", unit.fromLb(point.weightLb))
                        )
                        .foregroundStyle(.secondary)
                        .opacity(0.35)
                        .symbolSize(20)
                    }
                    ForEach(Array(model.smoothedHistory.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("7-day average", unit.fromLb(point.weightLb))
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    }
                    // Ground covered, as a faint ladder between the
                    // start and the target line. Quiet on purpose: the
                    // chart is already dense, so only the mark being
                    // worked toward carries a label — the rest read as
                    // rungs the line has crossed.
                    ForEach(Array((progress?.milestones ?? []).enumerated()), id: \.offset) { _, milestone in
                        RuleMark(y: .value("Milestone", unit.fromLb(milestone.weightLb)))
                            .foregroundStyle(.secondary)
                            .opacity(milestone.isReached ? 0.25 : 0.5)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 5]))
                            .annotation(position: .top, alignment: .trailing) {
                                if milestone.lostLb == nextMilestone?.lostLb {
                                    Text("\(unit.fromLb(milestone.lostLb), format: .number.precision(.fractionLength(0...1))) \(unit.symbol) down")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }
                    // The lose target or the maintenance hold-near
                    // anchor — same line, different name.
                    if let line = targetWeightLb, line > 0 {
                        RuleMark(y: .value(isMaintenance ? "Hold near" : "Target", unit.fromLb(line)))
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .annotation(position: .bottom, alignment: .leading) {
                                Text("\(isMaintenance ? "Hold near" : "Target") \(unit.fromLb(line), format: .number.precision(.fractionLength(targetDigits))) \(unit.symbol)")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                    }
                }
                .chartYScale(domain: unit.fromLb(model.trend.chartYDomain.lowerBound) ... unit.fromLb(model.trend.chartYDomain.upperBound))
                // One spoken sentence, not ~90 unlabeled point stops.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weight trend chart")
                .accessibilityValue(chartSummary)
                .frame(height: chartHeight)
                .padding(.vertical, 4)

            } else {
                Text("Weigh-ins from your scale will chart here once Apple Health has a few days of data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Between the chart and the projection: how far along, in
            // one glance, from a start the scale can't revise. Outside
            // the chart gate on purpose — a stamped start and a manual
            // weight are enough to answer this, and that combination
            // never draws a chart.
            if let progress {
                progressRow(progress)
            }

            if hasChart {
                if isMaintenance {
                    // Maintenance's counterpart to the projection line:
                    // is the scale holding?
                    if let drift = model.trend.driftLbPerWeek {
                        driftLabel(drift)
                    }
                } else if let window = model.trend.projectedWindow {
                    // The forecast, then the same question asked as a
                    // choice — one row, because the second line is only
                    // meaningful against the first.
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text("On this trend, you'll hit your target between \(window.lowerBound, format: .dateTime.month(.abbreviated).day()) and \(window.upperBound, format: .dateTime.month(.abbreviated).day())")
                        } icon: {
                            Image(systemName: "chart.line.downtrend.xyaxis")
                                .foregroundStyle(.green)
                        }
                        .font(.subheadline)
                        if let faster = model.trend.fasterWindow {
                            Text("With \(GoalTrendStats.paceBoostKcalPerDay, format: .number.precision(.fractionLength(0))) kcal/day more, between \(faster.lowerBound, format: .dateTime.month(.abbreviated).day()) and \(faster.upperBound, format: .dateTime.month(.abbreviated).day()).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if targetWeightLb != nil, !goalReached {
                    Text("No steady downward trend yet — a projection appears after a week of weigh-ins trending down.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Start → now → target. The bar answers "how far have I come",
    /// which a morning of water weight can't spoil the way it spoils the
    /// chart above it.
    private func progressRow(_ progress: GoalProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Progress")
                Spacer()
                Text(progressAmount(progress))
                    .monospacedDigit()
            }
            .font(.subheadline)
            ProgressView(value: progress.fraction)
                .tint(.green)
            // A derived start says so. It's the earliest weigh-in on
            // record, not the day the goal was set, and quoting the date
            // is what keeps the number honest for goals that predate the
            // stamp.
            if progress.isDerivedStart {
                Text("Since \(progress.startedAt, format: .dateTime.month(.abbreviated).day()), your earliest weigh-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        // One spoken sentence instead of a label, a bar, and a caption.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(progressSummary(progress))
    }

    /// "8.4 of 25 lb" — both numbers in the display unit.
    private func progressAmount(_ progress: GoalProgress) -> String {
        let lost = unit.fromLb(progress.lostLb)
            .formatted(.number.precision(.fractionLength(0...1)))
        let total = unit.fromLb(progress.totalLb)
            .formatted(.number.precision(.fractionLength(0...1)))
        return "\(lost) of \(total) \(unit.symbol)"
    }

    private func progressSummary(_ progress: GoalProgress) -> String {
        let percent = (progress.fraction * 100).formatted(.number.precision(.fractionLength(0)))
        let lost = unit.fromLb(progress.lostLb)
            .formatted(.number.precision(.fractionLength(0...1)))
        let total = unit.fromLb(progress.totalLb)
            .formatted(.number.precision(.fractionLength(0...1)))
        var summary = "\(lost) of \(total) \(unit.spoken) lost, \(percent) percent"
        if progress.isDerivedStart {
            summary += ", since \(progress.startedAt.formatted(.dateTime.month(.wide).day()))"
        }
        return summary
    }

    /// Copy the stored goal (or a blank slate) into the form fields.
    private func applyStoredGoal() {
        if let goal = goals.first {
            // 0 is the "no anchor parked" placeholder some historic
            // maintenance saves wrote — surface it as empty.
            targetWeightLb = goal.targetWeightLb > 0 ? goal.targetWeightLb : nil
            targetDate = goal.targetDate
            manualWeightLb = goal.fallbackCurrentWeightLb
            mode = goal.mode ?? GoalMode.lose
        } else {
            targetWeightLb = nil
            manualWeightLb = nil
            mode = GoalMode.lose
            targetDate = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
        }
    }

    /// The Cancel action: back out of un-saved edits and drop the
    /// keyboard.
    private func revertEdits() {
        applyStoredGoal()
        focusedField = nil
        deriveTrendStats()
    }

    /// The maintenance trend readout under the chart: is the scale
    /// holding? Direction gets its own SF Symbol (flat/down/up), so the
    /// tint is reinforcement, not the only signal.
    private func driftLabel(_ drift: Double) -> some View {
        let steady = abs(drift) < GoalTrendStats.steadyDriftThresholdLbPerWeek
        return Label {
            if steady, let anchor = targetWeightLb, anchor > 0 {
                Text("Holding near \(unit.fromLb(anchor), format: .number.precision(.fractionLength(targetDigits))) \(unit.symbol) — steady over the last 3 weeks")
            } else if steady {
                Text("Holding steady over the last 3 weeks")
            } else {
                Text("Trending \(drift < 0 ? "down" : "up") \(unit.fromLb(abs(drift)), format: .number.precision(.fractionLength(1))) \(unit.symbol)/week over the last 3 weeks")
            }
        } icon: {
            Image(systemName: steady
                ? "chart.line.flattrend.xyaxis"
                : drift < 0 ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis")
                .foregroundStyle(steady ? Color.green : drift > 0 ? Color.orange : Color.secondary)
        }
        .font(.subheadline)
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
        focusedField = nil
        ToastCenter.shared.show("Goal saved ✓")
    }

    private func removeGoal() {
        goals.forEach(context.delete)
        // Explicit save (GoalUpsert's discipline): a crash inside
        // autosave's window resurrected the removed goal.
        try? context.save()
        targetWeightLb = nil
        mode = GoalMode.lose
        focusedField = nil
        // push sends GoalUpdate.clear to the watch and reloads widgets.
        PhoneSyncService.shared.push(from: context)
        ReminderScheduler.shared.replan()
        ToastCenter.shared.show("Goal removed ✓")
    }
}
