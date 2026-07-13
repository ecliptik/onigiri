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
    @State private var healthWeightLb: Double?
    @State private var manualWeightLb: Double?
    @State private var targetWeightLb: Double?
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now

    private let health = HealthKitService()

    var body: some View {
        TabView(selection: $selection) {
            welcomePage.tag(0)
            healthPage.tag(1)
            goalPage.tag(2)
            waterPage.tag(3)
            donePage.tag(4)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        // Outside the tinted TabView — brand the links ourselves.
        .tint(.riceToast)
        .overlay(alignment: .topTrailing) {
            if selection < 4 {
                Button("Set Up Later") { finish() }
                    .font(.subheadline)
                    .padding()
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

    private var welcomePage: some View {
        page {
            Text("🍙")
                .font(.system(size: 72))
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
                .font(.system(size: 56))
                .foregroundStyle(.red)
            Text("Your log lives in Apple Health")
                .font(.title2.bold())
            Text("Onigiri reads and writes to Apple Health — nothing is stored online")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } action: {
            Button {
                Task {
                    if (try? await health.shouldRequestAuthorization()) == true {
                        try? await health.requestAuthorization()
                    }
                    healthRequested = true
                    healthWeightLb = try? await health.latestBodyMassLb()
                    withAnimation { selection = 2 }
                }
            } label: {
                Text(healthRequested ? "Continue" : "Allow Health Access")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.riceToast)
        }
    }

    private var goalPage: some View {
        page {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Set a goal")
                .font(.title2.bold())
            VStack(spacing: 12) {
                if let healthWeightLb {
                    LabeledContent("Current weight") {
                        Text("\(healthWeightLb, format: .number.precision(.fractionLength(1))) lb")
                    }
                } else {
                    LabeledContent("Current weight (lb)") {
                        TextField("0", value: $manualWeightLb, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                    }
                }
                LabeledContent("Target weight (lb)") {
                    TextField("0", value: $targetWeightLb, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
                DatePicker("By date", selection: $targetDate, in: Date.now..., displayedComponents: .date)
            }
            .padding(.horizontal)
            Text("Days that hit the daily deficit earn an onigiri. Change this in the Goal tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } action: {
            VStack(spacing: 6) {
                advanceButton(goalIsValid ? "Save Goal" : "Continue")
                if !goalIsValid {
                    Text("No goal set — any deficit earns the badge.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var waterPage: some View {
        page {
            Image(systemName: "drop.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("Daily water goal")
                .font(.title2.bold())
            Stepper(value: $waterGoalOz, in: 16...200, step: 8) {
                Text("\(waterGoalOz, format: .number.precision(.fractionLength(0))) oz")
                    .font(.title3.bold())
                    .monospacedDigit()
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
                .font(.system(size: 72))
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
            }
            .buttonStyle(.borderedProminent)
            .tint(.riceToast)
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
            withAnimation { selection += 1 }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.riceToast)
    }

    private var goalIsValid: Bool {
        guard let target = targetWeightLb, target > 0 else { return false }
        let current = healthWeightLb ?? manualWeightLb
        return current.map { target < $0 } ?? true
    }

    private func saveGoalIfValid() {
        guard goalIsValid, let target = targetWeightLb, goals.isEmpty else { return }
        context.insert(GoalSettings(
            targetWeightLb: target,
            targetDate: targetDate,
            fallbackCurrentWeightLb: healthWeightLb == nil ? manualWeightLb : nil
        ))
        try? context.save()
        PhoneSyncService.shared.push(from: context)
    }

    private func finish() {
        hasOnboarded = true
    }
}
