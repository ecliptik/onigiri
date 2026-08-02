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
    /// The "Progress since" override. Automatic (the earliest weigh-in
    /// on record) is the default and the way back; touching the date
    /// picker flips this off, exactly like leaving the custom burn field
    /// blank falls back to the recent average.
    @State private var startIsAutomatic = true
    @State private var startDate = Date.now
    @State private var loaded = false
    @State private var confirmingGoalRemoval = false
    /// Which weight field is editing — an enum (not a Bool) so moving
    /// directly between the two fields still fires the select-all
    /// onChange below.
    private enum WeightField: Hashable { case target, current }
    @FocusState private var focusedField: WeightField?

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

    /// The automatic start — the earliest weigh-in on record, and the
    /// floor of the date picker.
    private var automaticStart: WeightTrend.Point? {
        GoalProgress.automaticStart(in: model.weightHistory)
    }

    /// The explicit start the form currently describes, or nil for
    /// automatic. Note the unmoved case: while the picker still sits on
    /// the STORED date, the stored weight is the answer — looking it up
    /// again would quietly replace a stamped weight (which can come from
    /// a manual entry, with no weigh-in behind it) with whatever the
    /// scale happened to say nearest that day.
    private var formStart: (date: Date, weightLb: Double, manual: Bool)? {
        guard !startIsAutomatic else { return nil }
        if let goal = goals.first, let storedAt = goal.startedAt,
           let storedLb = goal.startWeightLb,
           Calendar.current.isDate(storedAt, inSameDayAs: startDate) {
            return (storedAt, storedLb, goal.startIsManual == true)
        }
        guard let weightLb = GoalProgress.startWeightLb(on: startDate, in: model.weightHistory)
        else { return nil }
        return (startDate, weightLb, true)
    }

    /// The form's start differs from the stored one — what makes Save
    /// light up for a start-only edit, and what tells GoalUpsert to
    /// write it.
    private var startEdited: Bool {
        let storedIsAutomatic = goals.first?.startedAt == nil
        if startIsAutomatic != storedIsAutomatic { return true }
        guard !startIsAutomatic, let storedAt = goals.first?.startedAt else { return false }
        return !Calendar.current.isDate(storedAt, inSameDayAs: startDate)
    }

    /// Start → now → target, against the LIVE form so an edited goal
    /// previews its own bar — target, start date and all. The start is
    /// what the form says, the stored stamp, or the earliest weigh-in on
    /// record for goals set before the stamp existed (kit rules, tested
    /// there). Milestones step in the display unit's round number —
    /// 5 lb, or 2 kg.
    private var progress: GoalProgress? {
        GoalProgress.resolve(
            startWeightLb: formStart?.weightLb,
            startedAt: formStart?.date,
            startIsManual: formStart?.manual ?? false,
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
            || startEdited
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
            || startEdited
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
            averageDailyBurnKcal: model.averageBurnKcal
        )
    }

    /// The plan the current form implies. Split out of `body` because
    /// the second budget row tipped the whole Form past what the type
    /// checker will attempt in one expression.
    @ViewBuilder
    private func dailyPlanSection(_ plan: CalorieBudget.Plan) -> some View {
        Section {
            if !isMaintenance, let current = currentWeightLb, let target = targetWeightLb {
                LabeledContent("To lose") {
                    Text("\(unit.fromLb(current - target), format: .number.precision(.fractionLength(1))) \(unit.symbol)")
                }
                LabeledContent("Deficit needed") {
                    Text("\(plan.requiredDailyDeficit, format: .number.precision(.fractionLength(0))) kcal/day")
                }
            }
            budgetRows(plan)
            // What the effort adds up to, independent of what the scale
            // did this morning — the number a bad weigh-in can't take
            // away (the user wanted something motivating that doesn't
            // swing).
            if model.trend.bankedLb > 0 {
                LabeledContent("Total deficit") {
                    Text("\(model.trend.bankedKcal, format: .number.precision(.fractionLength(0))) kcal ≈ \(unit.fromLb(model.trend.bankedLb), format: .number.precision(.fractionLength(1))) \(unit.symbol)")
                        .monospacedDigit()
                }
            }
            // Is the math showing up on the scale? Trailing 30 days of
            // deficit vs the smoothed weigh-in change.
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
        } header: {
            Text("Daily plan")
        } footer: {
            // Only the DIFFERENCE between the two rows. The section
            // below already explains what a budget is made of, and on
            // screen the two captions sit a thumb apart — both opening
            // "the day's own burn minus the deficit" read as a stutter.
            if todayBudget != nil {
                Text("Today's budget grows as you earn active burn. The average day uses your recent burn instead.")
            }
        }
    }

    /// TWO budgets, each named, because they answer different questions
    /// and shipping both under one label read as a contradiction: Goal
    /// said 2,293 while Details said 1,567 — 726 kcal apart at 1:43pm
    /// with nothing to tell them apart (the user, 2026-08-02). Both were
    /// right. One is what an average day allows; the other is what this
    /// day has earned so far, and it climbs as active burn comes in.
    @ViewBuilder
    private func budgetRows(_ plan: CalorieBudget.Plan) -> some View {
        LabeledContent("Average day") {
            Text("≈ \(plan.dailyBudget, format: .number.precision(.fractionLength(0))) kcal/day")
                .monospacedDigit()
        }
        if let todayBudget {
            LabeledContent("Today") {
                Text("\(todayBudget, format: .number.precision(.fractionLength(0))) kcal")
                    .monospacedDigit()
            }
        }
    }

    /// What TODAY allows, on the day's own burn — the same arithmetic
    /// Today and Details run, so the two screens quote one number. nil
    /// before Health has any burn for the day (and on the preview of a
    /// goal that can't be derived at all).
    private var todayBudget: Double? {
        guard let plan, model.todayDayBurnKcal > 0 else { return nil }
        return plan.requiredDailyDeficit >= model.todayDayBurnKcal
            ? 0
            : model.todayDayBurnKcal - plan.requiredDailyDeficit
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
                        Text("To hold steady, eat close to what you burn in a day. Landing within \(StreakCalendar.maintenanceBandKcal, format: .number.precision(.fractionLength(0))) kcal of even earns the day's badge.")
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
                    startSection
                } else {
                    holdNearSection
                }

                if let plan {
                    dailyPlanSection(plan)
                }

                // Its OWN section, deliberately outside `if let plan`:
                // what the budget is made of has to stay readable when
                // the plan can't be computed — goal reached, target
                // cleared — since that's exactly when someone comes
                // looking for why.
                //
                // No knobs any more. The Fixed style lived here until
                // 2026-08-02; a budget that stays put no matter what you
                // measure is the opposite of one you earn, so it went
                // with the model change rather than sitting beside it
                // meaning nothing.
                Section("Calorie budget") {
                    // "Resting burn, FULL DAY" — the bare label collided
                    // with Details', which shows what Health has
                    // recorded so far, and the two read as the app
                    // contradicting itself: 1,830 here against 1,272
                    // there (the user, 2026-08-02, one screen after the
                    // same mistake with "Calorie budget").
                    LabeledContent("Resting burn, full day") {
                        Text(model.estimatedRestingKcal.map {
                            "≈ \($0.formatted(.number.precision(.fractionLength(0)))) kcal/day"
                        } ?? "Not estimated")
                            .monospacedDigit()
                    }
                    LabeledContent("Average burn") {
                        // The fallback used to present as fact — the
                        // projection above inherits this guess.
                        Text(model.averageBurnKcal.map {
                            "≈ \($0.formatted(.number.precision(.fractionLength(0)))) kcal/day"
                        } ?? "≈ 2000 kcal/day (assumed)")
                            .monospacedDigit()
                    }
                    Text("Your budget is the day's own burn, minus the deficit. Resting burn counts from midnight — it happens whether or not you move. Active burn is added as you earn it, so a day without your watch has a smaller budget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.estimatedRestingKcal == nil {
                        Text("Add your height and date of birth in Health to estimate your resting burn. Without it, only the resting energy Health has already recorded counts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.averageBurnKcal == nil {
                        Text("No burn history in Health yet — the plan above assumes 2000 kcal/day until there is some.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    // MARK: - Progress since

    /// Where the progress bar and the chart's milestones measure from.
    /// Automatic by default and shown as such; moving the picker is the
    /// override, and the button is the way back — the same
    /// automatic-with-an-override shape as the units and the custom burn.
    ///
    /// Only rendered with weigh-ins on record: with none there is no
    /// date worth offering and nothing for a chosen one to measure.
    @ViewBuilder
    private var startSection: some View {
        if !isMaintenance, let earliest = automaticStart {
            Section {
                DatePicker(
                    "Date",
                    selection: startDateBinding,
                    in: startDateRange,
                    displayedComponents: .date
                )
                LabeledContent("Weight then") {
                    Text("\(unit.fromLb(formStart?.weightLb ?? earliest.weightLb), format: .number.precision(.fractionLength(1))) \(unit.symbol)")
                }
                if !startIsAutomatic {
                    Button("Use earliest weigh-in") { startIsAutomatic = true }
                }
            } header: {
                Text("Progress since")
            } footer: {
                Text(startIsAutomatic
                     ? "Automatic: your earliest weigh-in on record. Pick a date to measure from instead."
                     : "The progress bar and the chart's milestones measure from here. The weight is your weigh-in nearest this date.")
            }
        }
    }

    /// Reading it shows whatever start is in force; writing it IS the
    /// override, so picking a date needs no separate switch.
    private var startDateBinding: Binding<Date> {
        Binding(
            get: { startIsAutomatic ? (automaticStart?.date ?? startDate) : startDate },
            set: {
                startDate = $0
                startIsAutomatic = false
            }
        )
    }

    /// Earliest weigh-in through today. A stored start can predate the
    /// loaded history (Health is read 90 days back), so it widens the
    /// floor rather than sitting outside the picker's own range.
    private var startDateRange: ClosedRange<Date> {
        let now = Date.now
        let floor = [automaticStart?.date, goals.first?.startedAt]
            .compactMap(\.self)
            .min() ?? now
        return min(floor, now)...now
    }

    private var holdNearSection: some View {
        Section {
            targetWeightField
        } header: {
            Text("Hold near")
        } footer: {
            Text("The chart's reference line. The badge judges eating within what you burn, not the scale.")
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
            // Where the bar measures from. An inferred start names its
            // source — it's the earliest weigh-in on record, not the day
            // the goal was set, and saying so is what keeps the number
            // honest for goals that predate the stamp. A chosen start
            // just names the date; the control that set it is right
            // below. A stamp says nothing: it IS the starting day.
            switch progress.origin {
            case .earliestWeighIn:
                Text("Since \(progress.startedAt, format: .dateTime.month(.abbreviated).day()), your earliest weigh-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .chosen:
                Text("Since \(progress.startedAt, format: .dateTime.month(.abbreviated).day()).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .stamped:
                EmptyView()
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
        if progress.origin != .stamped {
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
            startIsAutomatic = goal.startedAt == nil
            startDate = goal.startedAt ?? automaticStart?.date ?? .now
        } else {
            targetWeightLb = nil
            manualWeightLb = nil
            mode = GoalMode.lose
            targetDate = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
            startIsAutomatic = true
            startDate = automaticStart?.date ?? .now
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
        // Only an actual start edit is sent — otherwise the stamp rule
        // stays in charge, and an untouched auto-stamped goal doesn't
        // quietly promote itself to a manual one.
        let startChange: GoalUpsert.StartChange? = startEdited
            ? formStart.map { .manual(at: $0.date, weightLb: $0.weightLb) } ?? .automatic
            : nil
        GoalUpsert.save(
            targetLb: target,
            targetDate: targetDate,
            healthWeightLb: model.healthWeightLb,
            manualWeightLb: manualWeightLb,
            mode: mode == GoalMode.lose ? nil : mode,
            startChange: startChange,
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
