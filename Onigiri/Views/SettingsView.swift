import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import WidgetKit
import OnigiriKit

/// App-wide settings: appearance choices and data portability.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "sfFork"
    @AppStorage(SharedStore.rewardIconKey, store: SharedStore.defaults) private var rewardIcon = "onigiri"
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0
    @AppStorage(SharedStore.balanceStyleKey, store: SharedStore.defaults) private var balanceStyle = "balance"
    @AppStorage(SharedStore.waterServingKey, store: SharedStore.defaults) private var waterServingOz = 12.0
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var waterGoalOz = 64.0
    @AppStorage(SharedStore.progressGaugesKey, store: SharedStore.defaults) private var progressGauges = false
    @AppStorage(SharedStore.showSodiumKey, store: SharedStore.defaults) private var showSodium = true
    @AppStorage(SharedStore.showWaterKey, store: SharedStore.defaults) private var showWater = true
    @AppStorage(SharedStore.remindMealsKey, store: SharedStore.defaults) private var remindMeals = false
    @AppStorage(SharedStore.remindWaterKey, store: SharedStore.defaults) private var remindWater = false
    @AppStorage(SharedStore.remindStreakKey, store: SharedStore.defaults) private var remindStreak = false
    @State private var notificationsDenied = false

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: LibraryJSONDocument?
    @State private var transferMessage: String?

    /// "Choose your own…" flow: which icon slot the emoji prompt edits,
    /// what was selected before (to restore on cancel/invalid), and the
    /// typed value.
    @State private var customIconSlot: IconSlot?
    @State private var customIconPrevious = ""
    @State private var customEmojiInput = ""

    enum IconSlot: String, Identifiable {
        case food = "Food icon"
        case water = "Water icon"
        case reward = "Goal badge"
        var id: String { rawValue }
    }

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
                // The public mirror — Forgejo is the push origin, GitHub
                // is the face.
                Link("https://github.com/ecliptik/onigiri",
                     destination: URL(string: "https://github.com/ecliptik/onigiri")!)
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

    private static let rewardIconOptions: [(tag: String, name: String)] = [
        ("onigiri", "Onigiri"),
        ("trophy", "Trophy"),
        ("medal", "Gold Medal"),
        ("star", "Star"),
        ("fire", "Fire"),
        ("muscle", "Strong"),
        ("target", "Bullseye"),
        ("sparkles", "Sparkles"),
    ]

    /// Appended to every icon picker: the current custom emoji (when one
    /// is set — otherwise the picker would show no selection) and the
    /// "Choose your own…" entry that opens the emoji prompt.
    @ViewBuilder
    private func customIconRows(current: String) -> some View {
        if SharedStore.isCustomEmoji(current) {
            HStack(spacing: 10) {
                Text(current)
                    .frame(width: 28)
                Text("Custom")
            }
            .tag(current)
        }
        HStack(spacing: 10) {
            Image(systemName: "face.smiling")
                .frame(width: 28)
                .foregroundStyle(.secondary)
            Text("Choose custom…")
        }
        .tag("custom")
    }

    /// Selecting "custom" opens the prompt — prefilled with the slot's
    /// current emoji, which the field selects so one keystroke replaces
    /// it. Any real selection syncs to the watch like before.
    private func iconChanged(_ slot: IconSlot, from old: String, to new: String) {
        if new == "custom" {
            customIconPrevious = old
            customEmojiInput = resolvedEmoji(for: slot, raw: old)
            customIconSlot = slot
        } else {
            PhoneSyncService.shared.push(from: context)
        }
    }

    private func commitCustomEmoji(for slot: IconSlot) {
        let value = customEmojiInput.trimmingCharacters(in: .whitespaces)
        if SharedStore.isCustomEmoji(value) {
            setIcon(slot, to: value)
        } else {
            setIcon(slot, to: customIconPrevious)
            ToastCenter.shared.show("One emoji only — keeping the old icon.")
        }
    }

    private func resolvedEmoji(for slot: IconSlot, raw: String) -> String {
        switch slot {
        case .food: SharedStore.foodEmoji(for: raw)
        case .water: SharedStore.waterEmoji(for: raw)
        case .reward: SharedStore.rewardEmoji(for: raw)
        }
    }

    private func iconRaw(for slot: IconSlot) -> String {
        switch slot {
        case .food: foodIcon
        case .water: waterIcon
        case .reward: rewardIcon
        }
    }

    private func setIcon(_ slot: IconSlot, to value: String) {
        switch slot {
        case .food: foodIcon = value
        case .water: waterIcon = value
        case .reward: rewardIcon = value
        }
    }

    private var backupCaption: String {
        // Files names the local location after the device ("On My iPad").
        let location = "Files → On My \(UIDevice.current.model) → Onigiri"
        guard let last = BackupService.lastBackupDate else {
            return "Backs up daily to \(location)."
        }
        let stamp = last.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "Last backup \(stamp), \(location)."
    }

    // Its own property, like dataSection: the icon pickers pushed the
    // inline Form past what the type-checker will solve in reasonable time.
    private var appearanceSection: some View {
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
                customIconRows(current: foodIcon)
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
                customIconRows(current: waterIcon)
            }
            .pickerStyle(.navigationLink)
            Picker("Goal badge", selection: $rewardIcon) {
                ForEach(Self.rewardIconOptions, id: \.tag) { option in
                    HStack(spacing: 10) {
                        Text(SharedStore.rewardEmoji(for: option.tag))
                            .frame(width: 28)
                        Text(option.name)
                    }
                    .tag(option.tag)
                }
                customIconRows(current: rewardIcon)
            }
            .pickerStyle(.navigationLink)
            Picker("Calorie display", selection: $balanceStyle) {
                Text("kcal balance").tag("balance")
                Text("kcal left").tag("remaining")
            }
            Toggle("Progress gauges", isOn: $progressGauges)
            // These hide the metrics themselves on Today, not
            // their fill bars (that misread cost a debug session).
            Toggle("Show sodium", isOn: $showSodium)
            Toggle("Show water", isOn: $showWater)
        }
        // The icon plumbing lives here, off the body's modifier chain —
        // adding it there pushed the whole Form past the type-checker.
        .onChange(of: foodIcon) { old, new in
            iconChanged(.food, from: old, to: new)
        }
        .onChange(of: waterIcon) { old, new in
            iconChanged(.water, from: old, to: new)
        }
        .onChange(of: rewardIcon) { old, new in
            iconChanged(.reward, from: old, to: new)
            // The gauge widgets and complications render the badge.
            WidgetCenter.shared.reloadAllTimelines()
        }
        .sheet(item: $customIconSlot) { slot in
            EmojiPromptSheet(
                title: slot.rawValue,
                input: $customEmojiInput,
                onUse: { commitCustomEmoji(for: slot); customIconSlot = nil },
                onCancel: { customIconSlot = nil }
            )
            // Swiping the sheet away counts as Cancel; commit already
            // rewrote the selection, so restoring is a no-op then.
            .onDisappear {
                if iconRaw(for: slot) == "custom" {
                    setIcon(slot, to: customIconPrevious)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection

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
                let denied: Bool = status == .denied
                let anyReminderOn: Bool = remindMeals || remindWater || remindStreak
                notificationsDenied = denied && anyReminderOn
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
                transferMessage = LibraryTransfer.handlePickedFile(result, context: context)
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
