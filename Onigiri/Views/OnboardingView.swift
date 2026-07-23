import SwiftUI
import SwiftData
import OnigiriKit

/// First-run onboarding: welcome → Health access with context → goal →
/// water goal → done. Every step is skippable ("Set Up Later") — the
/// app works goal-less. Shown once: ContentView gates on hasOnboarded
/// and an empty goal store.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query private var goals: [GoalSettings]
    @AppStorage(SharedStore.hasOnboardedKey, store: SharedStore.defaults) private var hasOnboarded = false
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var waterGoalOz = 64.0

    @State private var selection = 0
    @State private var healthRequested = false
    /// Reduce Motion: page advances cut instead of sliding.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRequestingHealth = false
    @State private var healthWeightLb: Double?
    @State private var manualWeightLb: Double?
    @State private var targetWeightLb: Double?

    /// Pre-Settings, so this is the Automatic (regional) resolution —
    /// a metric-region first run enters kg from the start. State and
    /// saves stay lb, same as GoalView.
    private var weightUnit: WeightUnit { SharedStore.weightUnit }

    private func weightDisplayBinding(_ source: Binding<Double?>) -> Binding<Double?> {
        Binding(
            get: { source.wrappedValue.map { (weightUnit.fromLb($0) * 10).rounded() / 10 } },
            set: { source.wrappedValue = $0.map(weightUnit.toLb) }
        )
    }
    @State private var averageBurnKcal: Double?
    /// Today's actual burn — the shared clamp's floor, same as Goal/Today.
    @State private var todayBurnKcal: Double = 0
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
    @FocusState private var weightFieldFocused: Bool

    // The copy scales with Dynamic Type; fixed glyphs looked undersized
    // beside it at accessibility sizes.
    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize = 72.0
    @ScaledMetric(relativeTo: .largeTitle) private var pageIconSize = 48.0

    private let health = HealthKitService()

    var body: some View {
        TabView(selection: $selection) {
            welcomePage.tag(0)
            healthPage.tag(1)
            goalPage.tag(2)
            waterPage.tag(3)
            privacyPage.tag(4)
            donePage.tag(5)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        // Outside the tinted TabView — brand the links ourselves.
        .tint(.riceToast)
        .overlay(alignment: .topTrailing) {
            // While a decimal field is focused, the corner slot becomes
            // the keyboard-dismiss (decimal pads have no return key —
            // same problem GoalView solved with its nav-bar Done).
            if weightFieldFocused {
                Button {
                    weightFieldFocused = false
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.onRicePaper)
                }
                .buttonStyle(.borderedProminent)
                .tint(.ricePaper)
                .padding()
            } else if selection < 5 {
                Button("Set Up Later") { finish() }
                    .font(.subheadline)
                    .padding()
            }
        }
        // Swiping past the Health page must not skip the request — it
        // otherwise fires contextlessly on Today right after onboarding,
        // the exact prompt this flow exists to avoid.
        .onChange(of: selection) { old, new in
            if old == 1, new > 1, !healthRequested {
                Task { await requestHealthAccess(advance: false) }
            }
        }
        // Select-all on focus, like the app's other decimal fields.
        .onReceive(NotificationCenter.default.publisher(
            for: UITextField.textDidBeginEditingNotification
        )) { note in
            guard let field = note.object as? UITextField else { return }
            DispatchQueue.main.async { field.selectAll(nil) }
        }
    }

    // MARK: - Pages

    // Both network-touching feature groups ship OFF (the user,
    // 2026-07-20: "nothing leaves the device until you say so") —
    // onboarding is the one offer; Settings owns them after. "Set Up
    // Later" leaves both off, which IS the default story.
    @AppStorage(SharedStore.onlineLookupsKey, store: SharedStore.defaults) private var onlineLookups = false
    @AppStorage(AIProviderSettings.enabledKey, store: SharedStore.defaults) private var aiEnabled = false

    private var privacyPage: some View {
        page {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: pageIconSize))
                .foregroundStyle(Color.nori)
            Text("Private by default")
                .font(.title2.bold())
            Text("Everything remains on your iPhone by default. Want online lookups or AI estimates? Turn them on here — or later in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 14) {
                Toggle(isOn: $onlineLookups) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Online food lookups")
                        Text("Barcode scans and food search, via OpenFoodFacts and USDA")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $aiEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI features")
                        Text("Estimates, label reading, and Identify Food — on-device by default")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
        } action: {
            advanceButton("Continue")
        }
    }

    private var welcomePage: some View {
        page {
            Text("🍙")
                .font(.system(size: heroIconSize))
            Text("Welcome to Onigiri")
                .font(.title.bold())
            Text("Calories, nutrition, and water logged to Apple Health")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } action: {
            advanceButton("Continue")
        }
    }

    private var healthPage: some View {
        page {
            Image(systemName: "heart.fill")
                .font(.system(size: pageIconSize * 56 / 48))
                .foregroundStyle(.red)
            Text("Your log lives in Apple Health")
                .font(.title2.bold())
            Text("Onigiri reads and writes to Apple Health — nothing is stored online")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } action: {
            Button {
                Task { await requestHealthAccess(advance: true) }
            } label: {
                Text(healthRequested ? "Continue" : "Allow Health Access")
                    .frame(maxWidth: .infinity)
                    // Dark-on-cream like the keyboard Done buttons: the
                    // default white label on riceToast fell to ~1.9:1
                    // contrast in dark mode.
                    .foregroundStyle(Color.onRicePaper)
            }
            .buttonStyle(.borderedProminent)
            .tint(.ricePaper)
            .disabled(isRequestingHealth)
        }
    }

    /// One path for the button and the swipe-past: request (once), then
    /// fetch what the goal page needs. Guarded — a double-tap used to
    /// spawn two authorization flows, and the completion yanked the
    /// selection back to page 2 from wherever the user had swiped.
    private func requestHealthAccess(advance: Bool) async {
        guard !isRequestingHealth else { return }
        isRequestingHealth = true
        defer { isRequestingHealth = false }
        if (try? await health.shouldRequestAuthorization()) == true {
            try? await health.requestAuthorization()
        }
        healthRequested = true
        healthWeightLb = try? await health.latestBodyMassLb()
        averageBurnKcal = (try? await health.averageDailyBurnKcal()) ?? nil
        todayBurnKcal = ((try? await health.todaySummary()) ?? .zero).totalBurnKcal
        if advance, selection == 1 {
            withAnimation(reduceMotion ? nil : .default) { selection = 2 }
        }
    }

    private var goalPage: some View {
        page {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: pageIconSize))
                .foregroundStyle(.green)
            Text("Set a goal")
                .font(.title2.bold())
            VStack(spacing: 12) {
                if let healthWeightLb {
                    LabeledContent("Current weight") {
                        Text("\(weightUnit.fromLb(healthWeightLb), format: .number.precision(.fractionLength(1))) \(weightUnit.symbol)")
                    }
                } else {
                    LabeledContent("Current weight (\(weightUnit.symbol))") {
                        TextField("0", value: weightDisplayBinding($manualWeightLb), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                            .focused($weightFieldFocused)
                    }
                }
                LabeledContent("Target weight (\(weightUnit.symbol))") {
                    TextField("0", value: weightDisplayBinding($targetWeightLb), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                        .focused($weightFieldFocused)
                }
                DatePicker("By date", selection: $targetDate, in: Date.now..., displayedComponents: .date)
            }
            .padding(.horizontal)
            // The plan the goal implies, before committing — GoalView
            // would have shown this; onboarding used to save blind.
            if let plan = previewPlan {
                VStack(spacing: 4) {
                    Text("≈ \(plan.requiredDailyDeficit, format: .number.precision(.fractionLength(0))) kcal/day deficit — budget ≈ \(plan.dailyBudget, format: .number.precision(.fractionLength(0))) kcal/day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if plan.isAggressive {
                        Label("That pace is aggressive — a later date means a gentler budget.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .multilineTextAlignment(.center)
            }
            Text("Days that hit the daily deficit earn an onigiri. You can adjust your goal anytime in the Goal tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } action: {
            VStack(spacing: 6) {
                advanceButton(goalValidation == .valid ? "Save Goal" : "Continue")
                if let caption = goalCaption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var waterPage: some View {
        page {
            Image(systemName: "drop.fill")
                .font(.system(size: pageIconSize))
                .foregroundStyle(.blue)
            Text("Daily water goal")
                .font(.title2.bold())
            // Steps in round display units (±8 oz / ±250 mL snapped);
            // storage stays oz. Pre-Settings this is the Automatic
            // (regional) unit, so a metric first run reads mL.
            Stepper {
                Text(SharedStore.waterUnit.text(fromOz: waterGoalOz))
                    .font(.title3.bold())
                    .monospacedDigit()
            } onIncrement: {
                if SharedStore.waterUnit == .fluidOunces {
                    waterGoalOz = min(200, waterGoalOz + 8)
                } else {
                    let ml = (WaterUnit.milliliters.fromOz(waterGoalOz) / 250).rounded() * 250
                    waterGoalOz = WaterUnit.milliliters.toOz(min(5_750, ml + 250))
                }
            } onDecrement: {
                if SharedStore.waterUnit == .fluidOunces {
                    waterGoalOz = max(16, waterGoalOz - 8)
                } else {
                    let ml = (WaterUnit.milliliters.fromOz(waterGoalOz) / 250).rounded() * 250
                    waterGoalOz = WaterUnit.milliliters.toOz(max(500, ml - 250))
                }
            }
            .padding(.horizontal, 40)
            Text("Sodium and water are tracked on Today by default — customize to use any nutrient in Settings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } action: {
            advanceButton("Continue")
        }
    }

    private var donePage: some View {
        page {
            Text("🍙")
                .font(.system(size: heroIconSize))
            Text("You're set")
                .font(.title.bold())
            Text("Make your first Log entry from Today's + button")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } action: {
            Button {
                finish()
            } label: {
                Text("Start Logging")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Color.onRicePaper)
            }
            .buttonStyle(.borderedProminent)
            .tint(.ricePaper)
        }
    }

    // MARK: - Pieces

    private func page(
        @ViewBuilder content: () -> some View,
        @ViewBuilder action: () -> some View
    ) -> some View {
        VStack(spacing: 16) {
            Spacer()
            content()
            Spacer()
            action()
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    private func advanceButton(_ title: String) -> some View {
        Button {
            if selection == 2 { saveGoalIfValid() }
            withAnimation(reduceMotion ? nil : .default) { selection += 1 }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color.onRicePaper)
        }
        .buttonStyle(.borderedProminent)
        .tint(.ricePaper)
    }

    /// Same rules as the Goal tab (one shared validator) — a goal used
    /// to save here with NO current weight, a half-state GoalView then
    /// couldn't edit.
    private var goalValidation: GoalUpsert.Validation {
        GoalUpsert.validate(targetLb: targetWeightLb, currentLb: healthWeightLb ?? manualWeightLb)
    }

    /// The plan a valid goal implies — the shared kit derivation
    /// (clamped burn, 2000 kcal cold-start until Health has history).
    private var previewPlan: CalorieBudget.Plan? {
        guard goalValidation == .valid else { return nil }
        return CalorieBudget.derivePlan(
            isMaintenance: false,
            currentWeightLb: healthWeightLb ?? manualWeightLb,
            targetWeightLb: targetWeightLb,
            targetDate: targetDate,
            averageDailyBurnKcal: averageBurnKcal,
            todayActualBurnKcal: TodayBurnFloor.ratcheted(todayBurnKcal)
        )
    }

    /// Say WHY the button reads "Continue" — the old copy claimed "no
    /// goal set" even when the user had typed one that couldn't save.
    private var goalCaption: String? {
        switch goalValidation {
        case .valid: nil
        case .missingTarget: "No goal set — any deficit earns the badge."
        case .missingCurrentWeight: "Enter your current weight to set a goal."
        case .targetNotBelowCurrent: "Target must be below your current weight."
        }
    }

    private func saveGoalIfValid() {
        guard goalValidation == .valid, let target = targetWeightLb else { return }
        // Upsert, not insert-once: swiping back to edit and re-tapping
        // "Save Goal" used to silently drop the change.
        GoalUpsert.save(
            targetLb: target,
            targetDate: targetDate,
            healthWeightLb: healthWeightLb,
            manualWeightLb: manualWeightLb,
            goals: goals,
            context: context
        )
    }

    private func finish() {
        hasOnboarded = true
    }
}
