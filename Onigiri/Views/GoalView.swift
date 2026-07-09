import SwiftUI
import SwiftData
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
    @State private var loaded = false
    @State private var savedToast = false

    private let health = HealthKitService()

    private var currentWeightLb: Double? { healthWeightLb ?? manualWeightLb }

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
                Section("Current weight") {
                    if let healthWeightLb {
                        LabeledContent("From Apple Health") {
                            Text("\(healthWeightLb, format: .number.precision(.fractionLength(1))) lb")
                        }
                    } else {
                        TextField("Current weight (lb)", value: $manualWeightLb, format: .number)
                            .keyboardType(.decimalPad)
                        Text("No weight in Apple Health yet — step on your scale, or enter it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Target") {
                    TextField("Target weight (lb)", value: $targetWeightLb, format: .number)
                        .keyboardType(.decimalPad)
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

                Section {
                    Button("Save goal") { save() }
                        .disabled(targetWeightLb == nil || currentWeightLb == nil)
                }
            }
            .navigationTitle("Goal")
            .overlay(alignment: .bottom) {
                if savedToast {
                    Text("Goal saved ✓")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: .capsule)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: savedToast)
        }
        .task {
            healthWeightLb = (try? await health.latestBodyMassLb()) ?? nil
            averageBurnKcal = (try? await health.averageDailyBurnKcal()) ?? nil
            if !loaded, let goal = goals.first {
                targetWeightLb = goal.targetWeightLb
                targetDate = goal.targetDate
                manualWeightLb = goal.fallbackCurrentWeightLb
                loaded = true
            }
        }
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
        savedToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            savedToast = false
        }
    }
}
