import SwiftUI
import SwiftData
import UIKit
import UserNotifications
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
    @AppStorage(SharedStore.trackedMetric1Key, store: SharedStore.defaults) private var trackedMetric1 = "sodium"
    @AppStorage(SharedStore.trackedMetric1ModeKey, store: SharedStore.defaults) private var trackedMetric1Mode = ""
    @AppStorage(SharedStore.trackedMetric1TargetKey, store: SharedStore.defaults) private var trackedMetric1Target = 0.0
    @AppStorage(SharedStore.trackedMetric1IconKey, store: SharedStore.defaults) private var trackedMetric1Icon = ""
    @AppStorage(SharedStore.trackedMetric2Key, store: SharedStore.defaults) private var trackedMetric2 = "water"
    @AppStorage(SharedStore.trackedMetric2ModeKey, store: SharedStore.defaults) private var trackedMetric2Mode = ""
    @AppStorage(SharedStore.trackedMetric2TargetKey, store: SharedStore.defaults) private var trackedMetric2Target = 0.0
    @AppStorage(SharedStore.trackedMetric2IconKey, store: SharedStore.defaults) private var trackedMetric2Icon = ""
    @AppStorage(SharedStore.energyStatsStyleKey, store: SharedStore.defaults) private var energyStatsStyle = "cards"
    @AppStorage(SharedStore.untrackedBelowKey, store: SharedStore.defaults) private var untrackedBelowKcal = 1000.0
    @AppStorage(SharedStore.remindMealsKey, store: SharedStore.defaults) private var remindMeals = false
    @AppStorage(SharedStore.remindWaterKey, store: SharedStore.defaults) private var remindWater = false
    @AppStorage(SharedStore.remindStreakKey, store: SharedStore.defaults) private var remindStreak = false
    @AppStorage(SharedStore.textSearchSourceKey, store: SharedStore.defaults) private var textSearchSource = SharedStore.textSearchSourceOFF
    @AppStorage(SharedStore.fdcAPIKeyKey, store: SharedStore.defaults) private var fdcAPIKey = ""
    /// What the key field shows; only plausible keys flow to storage.
    @State private var fdcAPIKeyDraft = SharedStore.fdcAPIKey
    /// The "Test Key" round-trip's verdict; editing the key voids it.
    @State private var fdcKeyTest = FDCKeyTest.idle

    enum FDCKeyTest: Equatable {
        case idle, testing, success
        case failure(String)
    }

    /// Which reset is awaiting its confirmation alert.
    @State private var pendingReset: PendingReset?

    enum PendingReset: String, Identifiable {
        case library, goals, settings, all
        var id: String { rawValue }

        var title: String {
            switch self {
            case .library: "Reset food library?"
            case .goals: "Reset goals?"
            case .settings: "Reset settings?"
            case .all: "Reset all?"
            }
        }

        var message: String {
            switch self {
            case .library:
                "Deletes every food and meal on this phone and the watch. Logged history in Apple Health is untouched, but the library can't be brought back — Export Library first if unsure."
            case .goals:
                "Removes the weight goal and its daily deficit history. Weight and logged history in Apple Health are untouched. This can't be undone."
            case .settings:
                "Returns every setting to its default, including tracked metrics, icons, reminders, and the online database API key. The food library and goals stay."
            case .all:
                "Resets Onigiri back to stock: food library, goals, and every setting. Apple Health data is untouched. This can't be undone."
            }
        }

        var toast: String {
            switch self {
            case .library: "Library reset"
            case .goals: "Goals reset"
            case .settings: "Settings reset"
            case .all: "Onigiri reset to stock"
            }
        }
    }
    @State private var notificationsDenied = false
    @State private var healthWriteDenied = false

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: LibraryJSONDocument?

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
        case metric1 = "First metric icon"
        case metric2 = "Second metric icon"
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
                    Text("Notifications are off for Onigiri — reminders won't appear.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("Turn On in Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
            #if DEBUG
            Button("Preview Reminders", systemImage: "bell.badge") {
                ReminderScheduler.shared.preview()
            }
            #endif
        } header: {
            Text("Reminders")
        } footer: {
            // The meal time lives in its toggle's label; only what the
            // rows can't say rides here.
            Text("Water pacing follows the Water section's goal, nudging at 11 AM, 3 PM, and 7 PM while you're behind; streaks check at 8 PM.")
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

    /// One probe request against FDC with the drafted key. The verdict
    /// only lands if the field still holds the key it judged.
    private func testFDCKey(_ key: String) {
        fdcKeyTest = .testing
        Task {
            let verdict: FDCKeyTest
            do {
                try await FoodDataCentralClient(apiKey: key).validateKey()
                verdict = .success
            } catch let error as FoodDataCentralError where error == .badAPIKey {
                verdict = .failure("FDC rejected this key")
            } catch let error as FoodDataCentralError where error.isBusy {
                verdict = .failure("FDC is busy — try again in a minute")
            } catch {
                verdict = .failure("Couldn't reach FDC")
            }
            if fdcAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) == key {
                fdcKeyTest = verdict
            }
        }
    }

    // The sodium limit lives inside its tracked-metric section; water
    // keeps its own — serving size is about the log buttons, and the
    // goal rides with it. Placed right under the tracked metrics: the
    // water slot's caption points here for its target.
    private var waterSection: some View {
        Section("Water") {
            Stepper(value: $waterServingOz, in: 4...40, step: 2) {
                LabeledContent("Serving size") {
                    Text("\(waterServingOz, format: .number.precision(.fractionLength(0))) oz")
                }
            }
            // The goal is drunk in servings, so stepping SNAPS to
            // multiples of the serving size (12 oz serving → 12,
            // 24, 36…) — plain ±serving from a goal set under an
            // old serving size stays misaligned forever, and the
            // tempting reset-to-0 escape hatch can't exist:
            // storage reads 0 as "unset → 64", so a 0 here would
            // show while the app secretly runs the fallback.
            // Floor = one serving, ceiling 200.
            Stepper {
                LabeledContent("Daily goal") {
                    Text("\(waterGoalOz, format: .number.precision(.fractionLength(0))) oz")
                }
            } onIncrement: {
                let serving = max(1, waterServingOz)
                let next = (floor(waterGoalOz / serving + 1e-9) + 1) * serving
                if next <= 200 { waterGoalOz = next }
            } onDecrement: {
                let serving = max(1, waterServingOz)
                let previous = (ceil(waterGoalOz / serving - 1e-9) - 1) * serving
                waterGoalOz = max(serving, previous)
            }
        }
    }

    /// Where text search looks things up. Barcode scans stay on
    /// OpenFoodFacts either way; FDC needs the user's own api.data.gov
    /// key (device-local, never synced — see PLAN-1.7).
    private var onlineDatabaseSection: some View {
        Section {
            Picker("Source", selection: $textSearchSource) {
                Text("OpenFoodFacts").tag(SharedStore.textSearchSourceOFF)
                Text("USDA FoodData Central (FDC)").tag(SharedStore.textSearchSourceFDC)
                Text("Both").tag(SharedStore.textSearchSourceBoth)
            }
            if textSearchSource != SharedStore.textSearchSourceOFF {
                // A plain TextField keeps the standard long-press
                // paste. It edits a DRAFT: only a plausible key (or a
                // deliberate clear) reaches storage, so a mis-paste
                // can't silently break search.
                TextField("API key", text: $fdcAPIKeyDraft)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .font(.callout.monospaced())
                    .onChange(of: fdcAPIKeyDraft) { _, raw in
                        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if key.isEmpty || SharedStore.isPlausibleFDCKey(key) {
                            fdcAPIKey = key
                        }
                        // A different key means the last verdict is
                        // about someone else.
                        fdcKeyTest = .idle
                    }
                let draft = fdcAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if draft.isEmpty {
                    Text("An API key is required to use the USDA FoodData Central, go to [fdc.nal.usda.gov/api-guide](https://fdc.nal.usda.gov/api-guide) to request a key")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if !SharedStore.isPlausibleFDCKey(draft) {
                    Text("API keys are 40 letters and digits — this one is \(draft.count) and won't be saved.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                HStack {
                    // Answers "is this key REAL?" at entry time — the
                    // shape check above can't know, and without this the
                    // first failed search is the messenger.
                    Button("Test API key") { testFDCKey(draft) }
                        .disabled(!SharedStore.isPlausibleFDCKey(draft) || fdcKeyTest == .testing)
                    Spacer()
                    switch fdcKeyTest {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView()
                    case .success:
                        Label("Success", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let reason):
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        } header: {
            Text("Online Database")
        } footer: {
            Text("[OpenFoodFacts](https://world.openfoodfacts.org) is always used for barcode scanning")
        }
    }

    // Its own property: inlining this pushed the Form past what the
    // type-checker will solve in reasonable time.
    private var dataSection: some View {
        Section {
            // Outcomes toast, like the same operations do from Foods
            // and the Log sheet — this screen used a third style
            // (sticky inline text).
            Button("Export Library…", systemImage: "square.and.arrow.up") {
                // Failure must say so — a button that silently does
                // nothing reads as a dead button.
                do {
                    exportDocument = LibraryJSONDocument(data: try LibraryTransfer.export(from: context))
                    showExporter = true
                } catch {
                    exportDocument = nil
                    ToastCenter.shared.show("Export failed: \(error.localizedDescription)")
                }
            }
            Button("Import Library…", systemImage: "square.and.arrow.down") {
                showImporter = true
            }
            Button("Back Up Now", systemImage: "externaldrive") {
                if BackupService.backupIfDue(context: context, force: true) != nil {
                    ToastCenter.shared.show("Backed up ✓")
                } else {
                    ToastCenter.shared.show("Backup failed.")
                }
            }
            Text(backupCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Data")
        }
    }

    /// Destructive resets, last on purpose — and Apple Health is never
    /// touched by any of them: HealthKit is the log store, its data
    /// outlives the app's library/settings by design.
    private var resetSection: some View {
        Section {
            Button("Reset Food Library", role: .destructive) { pendingReset = .library }
            Button("Reset Goals", role: .destructive) { pendingReset = .goals }
            Button("Reset Settings", role: .destructive) { pendingReset = .settings }
            Button("Reset All", role: .destructive) { pendingReset = .all }
        } header: {
            Text("Reset")
        } footer: {
            // The app's version/© colophon keeps the very bottom.
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

    /// Every preference key the settings reset returns to defaults.
    /// hasOnboarded is deliberately absent (a settings reset shouldn't
    /// replay onboarding); Reset All wipes the whole domain instead.
    private static let preferenceKeys: [String] = [
        SharedStore.waterServingKey, SharedStore.waterGoalKey,
        SharedStore.waterIconKey, SharedStore.foodIconKey, SharedStore.rewardIconKey,
        SharedStore.sodiumLimitKey, SharedStore.balanceStyleKey,
        SharedStore.progressGaugesKey, SharedStore.showSodiumKey, SharedStore.showWaterKey,
        SharedStore.remindMealsKey, SharedStore.remindWaterKey, SharedStore.remindStreakKey,
        SharedStore.trackedMetric1Key, SharedStore.trackedMetric1ModeKey,
        SharedStore.trackedMetric1TargetKey, SharedStore.trackedMetric1IconKey,
        SharedStore.trackedMetric2Key, SharedStore.trackedMetric2ModeKey,
        SharedStore.trackedMetric2TargetKey, SharedStore.trackedMetric2IconKey,
        SharedStore.untrackedBelowKey, SharedStore.energyStatsStyleKey,
        SharedStore.textSearchSourceKey, SharedStore.fdcAPIKeyKey,
    ]

    private func performReset(_ reset: PendingReset) {
        switch reset {
        case .library:
            guard deleteLibrary() else { return }
        case .goals:
            guard deleteGoals() else { return }
        case .settings:
            resetPreferences()
        case .all:
            guard deleteLibrary(), deleteGoals() else { return }
            // The whole domain, not just the preference list — stock
            // means the caches, the watch mirror, and the onboarding
            // flag go too (onboarding replays on next launch).
            SharedStore.defaults.removePersistentDomain(forName: SharedStore.appGroupID)
            fdcAPIKeyDraft = ""
            fdcKeyTest = .idle
        }
        // Reminders replan off the (possibly cleared) toggles; the push
        // rebuilds the watch mirror and reloads widgets.
        ReminderScheduler.shared.replan()
        PhoneSyncService.shared.push(from: context)
        ToastCenter.shared.show(reset.toast)
    }

    private func deleteLibrary() -> Bool {
        do {
            try LibraryMaintenance.wipeLibrary(context: context)
            return true
        } catch {
            ToastCenter.shared.show("Reset failed: \(error.localizedDescription)")
            return false
        }
    }

    private func deleteGoals() -> Bool {
        do {
            try LibraryMaintenance.wipeGoals(context: context)
        } catch {
            ToastCenter.shared.show("Reset failed: \(error.localizedDescription)")
            return false
        }
        DeficitTargetHistory.reset()
        return true
    }

    private func resetPreferences() {
        for key in Self.preferenceKeys {
            SharedStore.defaults.removeObject(forKey: key)
        }
        // The key field's draft mirrors storage by hand.
        fdcAPIKeyDraft = ""
        fdcKeyTest = .idle
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
    /// it. Storage never rests on the "custom" sentinel: the selection
    /// snaps straight back to the previous value and only Save writes
    /// the emoji, so a dismissed (or never-presented) sheet can't leave
    /// a checked-but-empty "Choose custom…" row behind.
    private func iconChanged(_ slot: IconSlot, from old: String, to new: String) {
        if new == "custom" {
            customIconPrevious = old
            customEmojiInput = resolvedEmoji(for: slot, raw: old)
            // Wait out the picker's pop before touching anything: writing
            // the selection back mid-pop aborts the pop, and the deferred
            // pop then tears down the freshly presented sheet.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                setIcon(slot, to: old)
                customIconSlot = slot
            }
        } else {
            PhoneSyncService.shared.push(from: context)
        }
    }

    /// Empty input is a cancellation, per Micheal — the previous choice
    /// simply stays. Only a non-empty non-emoji earns the toast.
    private func commitCustomEmoji(for slot: IconSlot) {
        let value = customEmojiInput.trimmingCharacters(in: .whitespaces)
        if SharedStore.isCustomEmoji(value) {
            setIcon(slot, to: value)
        } else if !value.isEmpty {
            ToastCenter.shared.show("One emoji only — keeping the old icon.")
        }
    }

    private func resolvedEmoji(for slot: IconSlot, raw: String) -> String {
        switch slot {
        case .food: SharedStore.foodEmoji(for: raw)
        case .water: SharedStore.waterEmoji(for: raw)
        case .reward: SharedStore.rewardEmoji(for: raw)
        case .metric1: SharedStore.customEmojiOrDefault(raw, for: slotNutrient(1))
        case .metric2: SharedStore.customEmojiOrDefault(raw, for: slotNutrient(2))
        }
    }

    private func setIcon(_ slot: IconSlot, to value: String) {
        switch slot {
        case .food: foodIcon = value
        case .water: waterIcon = value
        case .reward: rewardIcon = value
        case .metric1: trackedMetric1Icon = value
        case .metric2: trackedMetric2Icon = value
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
            // The water icon rides with the water metric's section below;
            // it only lives here when neither slot tracks water (it still
            // drives the log buttons and the watch).
            if !slotTracksWater {
                waterIconPicker
            }
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
            // "Compact" trades the Intake/Active/Resting cards for
            // Burned/Eaten beside the headline — more room for the log.
            Picker("Energy stats", selection: $energyStatsStyle) {
                Text("Cards").tag("cards")
                Text("Beside balance").tag("compact")
            }
            Toggle("Progress gauges", isOn: $progressGauges)
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
            // The push mirrors the badge into the shared defaults and
            // reloads the widgets when it actually changed.
            iconChanged(.reward, from: old, to: new)
        }
        // A new metric starts from its own defaults, not the old one's —
        // and every slot change syncs to the watch's metrics page.
        .onChange(of: trackedMetric1) {
            trackedMetric1Mode = ""
            trackedMetric1Target = 0
            trackedMetric1Icon = ""
            PhoneSyncService.shared.push(from: context)
        }
        .onChange(of: trackedMetric2) {
            trackedMetric2Mode = ""
            trackedMetric2Target = 0
            trackedMetric2Icon = ""
            PhoneSyncService.shared.push(from: context)
        }
        .onChange(of: sodiumLimitMg) { PhoneSyncService.shared.push(from: context) }
        .onChange(of: trackedMetric1Mode) { PhoneSyncService.shared.push(from: context) }
        .onChange(of: trackedMetric2Mode) { PhoneSyncService.shared.push(from: context) }
        .onChange(of: trackedMetric1Target) { PhoneSyncService.shared.push(from: context) }
        .onChange(of: trackedMetric2Target) { PhoneSyncService.shared.push(from: context) }
        .onChange(of: trackedMetric1Icon) { old, new in
            if new == "custom" {
                iconChanged(.metric1, from: old, to: new)
            } else {
                PhoneSyncService.shared.push(from: context)
            }
        }
        .onChange(of: trackedMetric2Icon) { old, new in
            if new == "custom" {
                iconChanged(.metric2, from: old, to: new)
            } else {
                PhoneSyncService.shared.push(from: context)
            }
        }
    }

    private var slotTracksWater: Bool {
        TrackedNutrient(key: trackedMetric1) == .water
            || TrackedNutrient(key: trackedMetric2) == .water
    }

    private var waterIconPicker: some View {
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
    }

    /// The slot's nutrient; nil when set to None (the slot is off).
    private func slotNutrient(_ slot: Int) -> TrackedNutrient? {
        let raw = slot == 1 ? trackedMetric1 : trackedMetric2
        if raw == SharedStore.trackedMetricNone { return nil }
        return TrackedNutrient(key: raw) ?? (slot == 1 ? .sodium : .water)
    }

    /// One of Today's two tracked-metric slots: metric (or None), type,
    /// target, icon. Sodium and water targets stay on their long-standing
    /// keys (nutrition detail, calendar, and reminders read those); water
    /// also brings the app-wide water icon picker. A None slot shows only
    /// the Metric row.
    @ViewBuilder
    private func trackedMetricSection(slot: Int) -> some View {
        let nutrient = slotNutrient(slot)
        Section {
            NavigationLink {
                NutrientPickerView(
                    selectionKey: slot == 1 ? $trackedMetric1 : $trackedMetric2,
                    takenKey: slotNutrient(slot == 1 ? 2 : 1)?.key
                )
            } label: {
                LabeledContent("Metric") { Text(nutrient?.displayName ?? "None") }
            }
            if let nutrient {
                // Menu, not segmented: segments ignore Dynamic Type.
                Picker("Type", selection: modeBinding(slot: slot, nutrient: nutrient)) {
                    Text("Limit").tag(TrackedMetricMode.limit.rawValue)
                    Text("Goal").tag(TrackedMetricMode.goal.rawValue)
                }
                .pickerStyle(.menu)
                switch nutrient {
                case .sodium:
                    // Generic in presentation; the value stays on the
                    // long-standing sodium-limit key.
                    LabeledContent("Target") {
                        HStack(spacing: 4) {
                            TextField("0", value: $sodiumLimitMg, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                            Text(nutrient.unitSymbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .water:
                    Text("Water's target is the daily goal in the Water section.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                default:
                    LabeledContent("Target") {
                        HStack(spacing: 4) {
                            TextField("0", value: targetBinding(slot: slot, nutrient: nutrient), format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                            Text(nutrient.unitSymbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if nutrient == .water {
                    // The app-wide water icon (watch and log buttons too).
                    waterIconPicker
                } else {
                    metricIconPicker(slot: slot, nutrient: nutrient)
                }
            }
        } header: {
            Text(slot == 1 ? "First tracked metric" : "Second tracked metric")
        }
        // Sodium's limit keeps coloring the calendar, day details, and
        // Today's log even when no slot tracks it — keep its knob
        // reachable (the water icon relocates the same way above).
        if slot == 2, !slotTracksSodium {
            Section {
                LabeledContent("Sodium limit") {
                    HStack(spacing: 4) {
                        TextField("0", value: $sodiumLimitMg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("mg")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Colors sodium in the calendar and day details even while untracked.")
            }
        }
    }

    private var slotTracksSodium: Bool {
        slotNutrient(1) == .sodium || slotNutrient(2) == .sodium
    }

    /// Default emoji or a custom pick — same prompt as the goal badge.
    private func metricIconPicker(slot: Int, nutrient: TrackedNutrient) -> some View {
        let stored = slot == 1 ? trackedMetric1Icon : trackedMetric2Icon
        return Picker("Icon", selection: slot == 1 ? $trackedMetric1Icon : $trackedMetric2Icon) {
            HStack(spacing: 10) {
                Text(nutrient.defaultEmoji)
                    .frame(width: 28)
                Text("Default")
            }
            .tag("")
            if SharedStore.isCustomEmoji(stored) {
                HStack(spacing: 10) {
                    Text(stored)
                        .frame(width: 28)
                    Text("Custom")
                }
                .tag(stored)
            }
            HStack(spacing: 10) {
                Image(systemName: "face.smiling")
                    .frame(width: 28)
                    .foregroundStyle(.secondary)
                Text("Choose custom…")
            }
            .tag("custom")
        }
        .pickerStyle(.navigationLink)
    }

    /// Empty stored mode means "the nutrient's default".
    private func modeBinding(slot: Int, nutrient: TrackedNutrient) -> Binding<String> {
        Binding(
            get: {
                let stored = slot == 1 ? trackedMetric1Mode : trackedMetric2Mode
                return stored.isEmpty ? nutrient.defaultMode.rawValue : stored
            },
            set: { value in
                if slot == 1 { trackedMetric1Mode = value } else { trackedMetric2Mode = value }
            }
        )
    }

    /// Zero stored target means "the nutrient's default" (an FDA daily
    /// value seed the user overwrites with their own number).
    private func targetBinding(slot: Int, nutrient: TrackedNutrient) -> Binding<Double> {
        Binding(
            get: {
                let stored = slot == 1 ? trackedMetric1Target : trackedMetric2Target
                return stored > 0 ? stored : nutrient.defaultTarget
            },
            set: { value in
                if slot == 1 { trackedMetric1Target = value } else { trackedMetric2Target = value }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // Only when write access is denied: every log fails with
                // an opaque toast otherwise, and iOS can't deep-link the
                // Health sharing pane — instructions are the recovery.
                if healthWriteDenied {
                    Section("Apple Health") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Health access is off — logging can't save.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                            Text("Turn it on in the Health app: Profile → Apps → Onigiri.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                appearanceSection

                trackedMetricSection(slot: 1)
                trackedMetricSection(slot: 2)

                // Right under the metrics: the water slot's caption
                // points here for its target.
                waterSection

                Section {
                    Stepper(value: $untrackedBelowKcal, in: 0...2000, step: 100) {
                        LabeledContent("Counts as untracked") {
                            Text(untrackedBelowKcal > 0
                                ? "< \(untrackedBelowKcal, format: .number.precision(.fractionLength(0))) kcal"
                                : "Off")
                        }
                    }
                    Text("Days with less logged break the streak and stay out of the month's totals. 0 turns this off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Untracked days")
                }

                remindersSection

                onlineDatabaseSection

                dataSection

                resetSection
            }
            .compactSections()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            // Centered alert, never confirmationDialog (the row-anchored
            // popover bubble) — the app-wide destructive-confirm rule.
            .alert(
                pendingReset?.title ?? "",
                isPresented: Binding(
                    get: { pendingReset != nil },
                    set: { if !$0 { pendingReset = nil } }
                ),
                presenting: pendingReset
            ) { reset in
                Button("Reset", role: .destructive) { performReset(reset) }
                Button("Cancel", role: .cancel) {}
            } message: { reset in
                Text(reset.message)
            }
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
                healthWriteDenied = HealthKitService().sharingDenied()
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
                switch result {
                case .success:
                    ToastCenter.shared.show("Library exported ✓")
                case .failure(let error):
                    ToastCenter.shared.show("Export failed: \(error.localizedDescription)")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                ToastCenter.shared.show(LibraryTransfer.handlePickedFile(result, context: context))
            }
            // On the outer chain deliberately: presenting from a Form
            // section tore down the whole Settings sheet moments after
            // this one appeared (the codebase's presentation landmine).
            .sheet(item: $customIconSlot) { slot in
                // The selection already snapped back before presenting;
                // only Save writes anything, so Cancel needs no cleanup.
                EmojiPromptSheet(
                    title: slot.rawValue,
                    input: $customEmojiInput,
                    onUse: { commitCustomEmoji(for: slot); customIconSlot = nil },
                    onCancel: { customIconSlot = nil }
                )
            }
        }
        // Transfer/backup outcomes toast; a sheet needs its own host
        // (the root's renders behind presented sheets).
        .toastHost()
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
