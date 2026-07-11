import SwiftUI
import SwiftData
import UserNotifications
import OnigiriKit

/// App-wide settings: appearance choices and data portability.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "sfFork"
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0
    @AppStorage(SharedStore.balanceStyleKey, store: SharedStore.defaults) private var balanceStyle = "balance"
    @AppStorage(SharedStore.waterServingKey, store: SharedStore.defaults) private var waterServingOz = 12.0
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var waterGoalOz = 64.0
    @AppStorage(SharedStore.remindMealsKey, store: SharedStore.defaults) private var remindMeals = false
    @AppStorage(SharedStore.remindWaterKey, store: SharedStore.defaults) private var remindWater = false
    @AppStorage(SharedStore.remindStreakKey, store: SharedStore.defaults) private var remindStreak = false
    @State private var notificationsDenied = false

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: LibraryJSONDocument?
    @State private var transferMessage: String?

    /// All opt-in, fixed times (see the footer); permission is requested
    /// the first time a toggle turns on, never at launch.
    private var remindersSection: some View {
        Section {
            Toggle("Not logged by 2 PM", isOn: $remindMeals)
            Toggle("Water pacing", isOn: $remindWater)
            Toggle("Streak about to lapse", isOn: $remindStreak)
            if notificationsDenied {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notifications are off for Onigiri, so reminders can't fire.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("Turn on in Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
            #if DEBUG
            Button("Preview reminders", systemImage: "bell.badge") {
                ReminderScheduler.shared.preview()
            }
            #endif
        } header: {
            Text("Reminders")
        } footer: {
            Text("Meals check in at 2 PM, water at 11 AM, 3 PM, and 7 PM while you're behind, streaks at 8 PM.")
        }
    }

    private func reminderToggled(_ on: Bool) {
        if on {
            Task {
                let granted = await ReminderScheduler.shared.requestPermission()
                notificationsDenied = !granted
            }
        } else {
            ReminderScheduler.shared.replan()
        }
    }

    // Its own property: inlining this pushed the Form past what the
    // type-checker will solve in reasonable time.
    private var dataSection: some View {
        Section {
            Button("Export library…", systemImage: "square.and.arrow.up") {
                exportDocument = (try? LibraryTransfer.export(from: context)).map(LibraryJSONDocument.init)
                showExporter = exportDocument != nil
            }
            Button("Import library…", systemImage: "square.and.arrow.down") {
                showImporter = true
            }
            Button("Back up now", systemImage: "externaldrive") {
                if BackupService.backupIfDue(context: context, force: true) != nil {
                    transferMessage = "Backed up ✓"
                } else {
                    transferMessage = "Backup failed."
                }
            }
            if let transferMessage {
                Text(transferMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(backupCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Data")
        } footer: {
            VStack(spacing: 2) {
                Text("Onigiri \(Bundle.main.appVersion)")
                Text("© 2026 Micheal Waltz")
                Link("https://forgejo.ecliptik.com/ecliptik/onigiri",
                     destination: URL(string: "https://forgejo.ecliptik.com/ecliptik/onigiri")!)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    private static let foodIconOptions: [(tag: String, name: String)] = [
        ("sfFork", "Fork & Knife"),
        ("apple", "Apple"),
        ("bento", "Bento"),
        ("noodles", "Noodles"),
        ("fork", "Fork & Knife"),
        ("plate", "Plate"),
        ("onigiri", "Onigiri"),
    ]

    private static let waterIconOptions: [(tag: String, name: String)] = [
        ("sfDrop", "Droplet"),
        ("drop", "Droplet"),
        ("wave", "Great Wave"),
        ("cup", "Cup"),
        ("tap", "Tap"),
        ("pour", "Pour"),
        ("ice", "Ice"),
    ]

    private var backupCaption: String {
        guard let last = BackupService.lastBackupDate else {
            return "Backs up daily to Files → On My iPhone → Onigiri."
        }
        let stamp = last.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "Last backup \(stamp), Files → On My iPhone → Onigiri."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    // navigationLink style: menu pickers strip both image
                    // attachments and icon colors from their rows; a pushed
                    // list renders real SwiftUI rows — true colors, aligned
                    // icon column.
                    Picker("Food icon", selection: $foodIcon) {
                        ForEach(Self.foodIconOptions, id: \.tag) { option in
                            HStack(spacing: 10) {
                                FoodIconView(raw: option.tag)
                                    .frame(width: 28)
                                Text(option.name)
                            }
                            .tag(option.tag)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Picker("Water icon", selection: $waterIcon) {
                        ForEach(Self.waterIconOptions, id: \.tag) { option in
                            HStack(spacing: 10) {
                                WaterIconView(raw: option.tag)
                                    .frame(width: 28)
                                Text(option.name)
                            }
                            .tag(option.tag)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Picker("Calorie display", selection: $balanceStyle) {
                        Text("kcal balance").tag("balance")
                        Text("kcal left").tag("remaining")
                    }
                    Text("kcal left counts down what you can still eat today while staying on your deficit goal. kcal balance shows intake minus burn.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                remindersSection

                Section("Water") {
                    Stepper(value: $waterServingOz, in: 4...40, step: 2) {
                        LabeledContent("Serving size") {
                            Text("\(waterServingOz, format: .number.precision(.fractionLength(0))) oz")
                        }
                    }
                    Stepper(value: $waterGoalOz, in: 16...200, step: 8) {
                        LabeledContent("Daily goal") {
                            Text("\(waterGoalOz, format: .number.precision(.fractionLength(0))) oz")
                        }
                    }
                }

                Section("Sodium") {
                    Stepper(value: $sodiumLimitMg, in: 500...6000, step: 100) {
                        LabeledContent("Daily limit") {
                            Text("\(sodiumLimitMg, format: .number.precision(.fractionLength(0))) mg")
                        }
                    }
                    Text("The FDA guideline is 2,300 mg sodium for adults.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                dataSection
            }
            .compactSections()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: balanceStyle) {
                // The watch mirrors this setting; sync it right away.
                PhoneSyncService.shared.push(from: context)
            }
            .onChange(of: waterServingOz) {
                // The watch's water button uses the serving size too.
                PhoneSyncService.shared.push(from: context)
            }
            .onChange(of: waterGoalOz) {
                PhoneSyncService.shared.push(from: context)
                // The pacing checkpoints scale off the goal.
                ReminderScheduler.shared.replan()
            }
            .onChange(of: remindMeals) { _, on in reminderToggled(on) }
            .onChange(of: remindWater) { _, on in reminderToggled(on) }
            .onChange(of: remindStreak) { _, on in reminderToggled(on) }
            .task {
                // Surface an existing denial as soon as Settings opens with
                // any reminder switched on.
                let status = await UNUserNotificationCenter.current()
                    .notificationSettings().authorizationStatus
                notificationsDenied = status == .denied
                    && (remindMeals || remindWater || remindStreak)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
    }
}

extension Bundle {
    /// The full semantic version ("1.0.1") for the Settings footer.
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
