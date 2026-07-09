import SwiftUI
import SwiftData
import OnigiriKit

/// Home screen: the daily calorie meter, goal gauge, and today's log.
struct TodayView: View {
    @State private var model = TodayModel()
    @Environment(\.scenePhase) private var scenePhase
    @Query private var goals: [GoalSettings]
    @AppStorage("waterGoalOz") private var waterGoalOz = 64.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    balanceHeadline
                    goalCard
                    meterGrid
                    hydrationRow
                    loggedSection

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Today")
        }
        .task { await model.start() }
        .refreshable { await model.refresh() }
        .onAppear { Task { await model.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }

    // MARK: - Sections

    private var balanceHeadline: some View {
        VStack(spacing: 4) {
            Text(model.summary.balanceKcal, format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(model.summary.balanceKcal <= 0 ? Color.green : Color.orange)
                .contentTransition(.numericText())
            Text("kcal balance today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var goalCard: some View {
        if let goal = goals.first, let plan = plan(for: goal) {
            DailyGoalCard(
                bankedKcal: max(0, -model.summary.balanceKcal),
                intakeKcal: model.summary.intakeKcal,
                plan: plan
            )
        } else {
            Text(goals.isEmpty
                 ? "Set a weight goal in the Goal tab to track your daily deficit here."
                 : "Add a weigh-in (or set your current weight in the Goal tab) to track your daily deficit.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func plan(for goal: GoalSettings) -> CalorieBudget.Plan? {
        guard let weight = model.currentWeightLb ?? goal.fallbackCurrentWeightLb else { return nil }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: .now), to: goal.targetDate
        ).day ?? 0
        return CalorieBudget.plan(
            currentWeightLb: weight,
            targetWeightLb: goal.targetWeightLb,
            daysRemaining: days,
            averageDailyBurn: model.expectedDailyBurnKcal
        )
    }

    private var meterGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MeterCell(label: "Intake", value: model.summary.intakeKcal, systemImage: "fork.knife", tint: .orange)
                MeterCell(label: "Active", value: model.summary.activeBurnKcal, systemImage: "flame.fill", tint: .red)
                MeterCell(label: "Resting", value: model.summary.restingBurnKcal, systemImage: "bed.double.fill", tint: .indigo)
            }
        }
        .padding(.horizontal)
    }

    private var hydrationRow: some View {
        HStack(spacing: 12) {
            Label {
                Text("\(model.summary.sodiumMg, format: .number.precision(.fractionLength(0))) mg sodium")
            } icon: {
                Image(systemName: "aqi.medium").foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity)

            Label {
                Text("\(model.summary.waterOz, format: .number.precision(.fractionLength(0))) / \(waterGoalOz, format: .number.precision(.fractionLength(0))) oz water")
            } icon: {
                Image(systemName: "drop.fill").foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
    }

    private var loggedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logged today")
                .font(.headline)
                .padding(.horizontal)

            if model.foodLog.isEmpty {
                Text("Nothing logged yet — tap a food or meal in the Foods tab.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            ForEach(model.foodLog) { entry in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                        Text(entry.date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(entry.kcal, format: .number.precision(.fractionLength(0))) kcal")
                            .monospacedDigit()
                        Text("\(entry.sodiumMg, format: .number.precision(.fractionLength(0))) mg Na")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button {
                        Task { await model.delete(entry) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
}

struct DailyGoalCard: View {
    let bankedKcal: Double
    let intakeKcal: Double
    let plan: CalorieBudget.Plan

    private var progress: Double {
        plan.requiredDailyDeficit > 0 ? bankedKcal / plan.requiredDailyDeficit : 1
    }
    private var remainingKcal: Double { plan.dailyBudget - intakeKcal }

    var body: some View {
        HStack(spacing: 16) {
            OnigiriGauge(progress: progress)
                .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Daily goal")
                        .font(.headline)
                    Text("\(Int((max(0, min(1, progress))) * 100))%")
                        .font(.headline)
                        .foregroundStyle(progress >= 1 ? Color.green : Color.secondary)
                }
                Text("\(bankedKcal, format: .number.precision(.fractionLength(0))) of \(plan.requiredDailyDeficit, format: .number.precision(.fractionLength(0))) kcal deficit banked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if remainingKcal >= 0 {
                    Text("≈ \(remainingKcal, format: .number.precision(.fractionLength(0))) kcal left to eat today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("≈ \(-remainingKcal, format: .number.precision(.fractionLength(0))) kcal over budget")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                if plan.isAggressive {
                    Label("Aggressive pace — consider a later date", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        .padding(.horizontal)
    }
}

struct MeterCell: View {
    let label: String
    let value: Double
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
