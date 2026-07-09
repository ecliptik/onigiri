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
    @State private var loaded = false
    @State private var savedToast = false
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: LibraryJSONDocument?
    @State private var transferMessage: String?
    @FocusState private var weightFieldFocused: Bool

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
                            .focused($weightFieldFocused)
                        Text("No weight in Apple Health yet — step on your scale, or enter it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Target") {
                    TextField("Target weight (lb)", value: $targetWeightLb, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($weightFieldFocused)
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

                trendSection

                Section {
                    Button("Save goal") { save() }
                        .disabled(targetWeightLb == nil || currentWeightLb == nil)
                }

                Section("Data") {
                    Button("Export library…", systemImage: "square.and.arrow.up") {
                        exportDocument = (try? LibraryTransfer.export(from: context)).map(LibraryJSONDocument.init)
                        showExporter = exportDocument != nil
                    }
                    Button("Import library…", systemImage: "square.and.arrow.down") {
                        showImporter = true
                    }
                    if let transferMessage {
                        Text(transferMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Foods, meals, goal, and water settings as JSON. Daily logs live in Apple Health — export those from the Health app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Goal")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
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
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "onigiri-library"
            ) { result in
                if case .success = result {
                    transferMessage = "Library exported ✓"
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        transferMessage = try LibraryTransfer.importData(data, into: context)
                        PhoneSyncService.shared.push(from: context)
                    } catch {
                        transferMessage = "Import failed: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    transferMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
        .task {
            healthWeightLb = (try? await health.latestBodyMassLb()) ?? nil
            averageBurnKcal = (try? await health.averageDailyBurnKcal()) ?? nil
            weightHistory = (try? await health.bodyMassHistory()) ?? []
            if !loaded, let goal = goals.first {
                targetWeightLb = goal.targetWeightLb
                targetDate = goal.targetDate
                manualWeightLb = goal.fallbackCurrentWeightLb
                loaded = true
            }
        }
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
        Section("Weight trend") {
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
        savedToast = true
        PhoneSyncService.shared.push(from: context)
        Task {
            try? await Task.sleep(for: .seconds(2))
            savedToast = false
        }
    }
}
