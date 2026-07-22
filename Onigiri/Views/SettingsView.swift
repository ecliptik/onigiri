import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import OnigiriKit

/// App-wide settings: appearance choices and data portability.
/// An hour-and-minute picker over a minutes-since-midnight setting.
private struct ReminderTimeRow: View {
    let label: String
    @Binding var minute: Int

    var body: some View {
        DatePicker(
            label,
            selection: Binding(
                get: {
                    Calendar.current.date(
                        bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now
                    ) ?? .now
                },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                }
            ),
            displayedComponents: .hourAndMinute
        )
    }
}

/// Round-trip verdict for key/connection tests (FDC and AI share the
/// grammar); editing the tested value voids it back to idle.
enum FDCKeyTest: Equatable {
    case idle, testing, success
    case failure(String)
}

/// Footnote warning whose COLOR rides the icon: orange text on the light
/// rice canvas measures ≈2.2:1 (2026-07-22 audit, WCAG AA needs 4.5:1) —
/// the words stay primary, the triangle carries the urgency. Same
/// glyph-not-color move as the DWC status twins.
private struct WarningFootnote: View {
    private let content: Text

    init(_ key: LocalizedStringKey) { content = Text(key) }
    init(verbatim: String) { content = Text(verbatim) }

    var body: some View {
        Label {
            content.foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .font(.footnote)
    }
}

/// Icon-picker option lists + the custom-emoji rows, shared between the
/// main screen (water picker, metric slots) and the Appearance subscreen.
private enum SettingsIcons {
    static let foodOptions: [(tag: String, name: String)] = [
        ("sfFork", "Fork & Knife"),
        ("apple", "Apple"),
        ("bento", "Bento"),
        ("noodles", "Noodles"),
        ("fork", "Fork & Knife"),
        ("plate", "Plate"),
        ("onigiri", "Onigiri"),
    ]

    static let waterOptions: [(tag: String, name: String)] = [
        ("sfDrop", "Droplet"),
        ("drop", "Droplet"),
        ("wave", "Great Wave"),
        ("cup", "Cup"),
        ("tap", "Tap"),
        ("pour", "Pour"),
        ("ice", "Ice"),
    ]

    static let rewardOptions: [(tag: String, name: String)] = [
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
    static func customRows(current: String) -> some View {
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
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Foreground return re-checks the permission banners (denials may
    /// have been fixed in the system round trip our own buttons start).
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "sfFork"
    @AppStorage(SharedStore.rewardIconKey, store: SharedStore.defaults) private var rewardIcon = "onigiri"
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0
    @AppStorage(SharedStore.balanceStyleKey, store: SharedStore.defaults) private var balanceStyle = "remaining"
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
    @AppStorage(SharedStore.remindMealsKey, store: SharedStore.defaults) private var remindMeals = false
    @AppStorage(SharedStore.remindWaterKey, store: SharedStore.defaults) private var remindWater = false
    @AppStorage(SharedStore.remindStreakKey, store: SharedStore.defaults) private var remindStreak = false
    // Reminder times (minutes since midnight); defaults mirror
    // ReminderPlanner.Times so an untouched install schedules exactly
    // the original fixed times.
    @AppStorage(SharedStore.remindMealsMinuteKey, store: SharedStore.defaults) private var remindMealsMinute = 14 * 60
    @AppStorage(SharedStore.remindStreakMinuteKey, store: SharedStore.defaults) private var remindStreakMinute = 20 * 60
    @AppStorage(SharedStore.remindWaterMinute1Key, store: SharedStore.defaults) private var remindWaterMinute1 = 11 * 60
    @AppStorage(SharedStore.remindWaterMinute2Key, store: SharedStore.defaults) private var remindWaterMinute2 = 15 * 60
    @AppStorage(SharedStore.remindWaterMinute3Key, store: SharedStore.defaults) private var remindWaterMinute3 = 19 * 60
    @AppStorage(SharedStore.onlineLookupsKey, store: SharedStore.defaults) private var onlineLookups = false
    @AppStorage(SharedStore.textSearchSourceKey, store: SharedStore.defaults) private var textSearchSource = SharedStore.textSearchSourceOFF
    // Raw unit preferences ("auto"/explicit). Observed HERE (not just in
    // the Units subscreen) so the summary row updates and the onChange
    // sync push fires from a view that stays mounted.
    @AppStorage(SharedStore.weightUnitKey, store: SharedStore.defaults) private var weightUnit = SharedStore.unitAutomatic
    @AppStorage(SharedStore.waterUnitKey, store: SharedStore.defaults) private var waterUnit = SharedStore.unitAutomatic
    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults) private var sodiumUnit = SharedStore.unitAutomatic
    /// The Keychain key as Settings found it; Cancel restores it (the
    /// field applies as-you-go like the rest of Settings, and the FDC key
    /// is no longer in the defaults snapshot). The draft/test/reveal
    /// state lives in OnlineDatabaseSettingsScreen — each push re-reads
    /// storage, so resets and Cancel need no hand-mirroring there.
    @State private var fdcKeyAtOpen = SharedStore.fdcAPIKey

    // Bring-your-own-AI: only the two values the summary row reads live
    // here now — the full configuration (models, server, secrets, test)
    // moved into AISettingsScreen with its own state.
    @AppStorage(AIProviderSettings.enabledKey, store: SharedStore.defaults) private var aiEnabled = false
    @AppStorage(AIProviderSettings.providerKey, store: SharedStore.defaults) private var aiProvider = AIProvider.onDevice.rawValue

    /// Which reset is awaiting its confirmation alert.
    @State private var pendingReset: PendingReset?

    enum PendingReset: String, Identifiable {
        case library, goals, settings, all
        var id: String { rawValue }

        var title: String {
            switch self {
            case .library: "Reset Food Library?"
            case .goals: "Reset goals?"
            case .settings: "Reset settings?"
            case .all: "Reset all?"
            }
        }

        var message: String {
            switch self {
            case .library:
                "Deletes every food and meal on this phone and the watch. Logged history in Apple Health is untouched, but the Food Library can't be brought back — Export Food Library first if unsure."
            case .goals:
                "Removes the weight goal and its daily deficit history. Weight and logged history in Apple Health are untouched. This can't be undone."
            case .settings:
                "Returns every setting to its default, including tracked metrics, icons, reminders, the online database API key, and the AI provider setup. The Food Library and goals stay."
            case .all:
                "Resets Onigiri back to stock: Food Library, goals, and every setting. Apple Health data is untouched. This can't be undone."
            }
        }

        var toast: String {
            switch self {
            case .library: "Food Library reset"
            case .goals: "Goals reset"
            case .settings: "Settings reset"
            case .all: "Onigiri reset to stock"
            }
        }
    }
    @State private var notificationsDenied = false
    @State private var healthWriteDenied = false
    /// Cancel-with-edits confirmation (the forms' discard grammar).
    @State private var confirmDiscard = false
    /// The deferred emoji-prompt presentation — stored so a Cancel (or a
    /// newer pick) can cancel it: an orphaned task wrote the old icon
    /// back AFTER the sheet was dismissed (2026-07-22 audit).
    @State private var pendingCustomIconTask: Task<Void, Never>?

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

    /// The configure-once features, one NavigationLink row each — the
    /// user's de-clutter call (2026-07-21): daily-relevant sections keep
    /// the main screen, plumbing collapses behind rows. The trailing
    /// values keep the privacy posture visible at a glance — Online
    /// Database and AI must still SAY "Off" from the main screen
    /// (off-by-default is the app's spine).
    private var configSection: some View {
        Section {
            NavigationLink {
                AppearanceSettingsScreen()
            } label: {
                Text("Appearance")
            }
            NavigationLink {
                RemindersSettingsScreen(notificationsDenied: $notificationsDenied)
            } label: {
                LabeledContent("Reminders") { Text(remindersSummary) }
            }
            NavigationLink {
                OnlineDatabaseSettingsScreen()
            } label: {
                LabeledContent("Online Database") { Text(onlineDatabaseSummary) }
            }
            NavigationLink {
                AISettingsScreen()
            } label: {
                LabeledContent("AI") { Text(aiSummary) }
            }
            NavigationLink {
                UnitsSettingsView()
            } label: {
                LabeledContent("Units") {
                    Text("\(WeightUnit.resolve(weightUnit).symbol) · \(resolvedWaterUnit.symbol) · \(resolvedSodiumUnit.symbol)")
                }
            }
        }
        // The icon/metric/unit sync plumbing stays on THIS always-mounted
        // section — the subscreens write the same defaults keys, and these
        // observers must keep firing for edits made there (and for the
        // reset sweep). Plain-push observers ride ARRAY bundles: fifteen
        // stacked onChanges is 3× the size that already blew this file's
        // type-checker budget once (the reminder-minutes lesson).
        .onChange(of: [weightUnit, waterUnit, sodiumUnit]) {
            PhoneSyncService.shared.push(from: context)
        }
        .onChange(of: [trackedMetric1Mode, trackedMetric2Mode]) {
            PhoneSyncService.shared.push(from: context)
        }
        .onChange(of: [sodiumLimitMg, trackedMetric1Target, trackedMetric2Target]) {
            PhoneSyncService.shared.push(from: context)
        }
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

    // The trailing values must tell the FUNCTIONAL truth, not stored
    // intent — "2 on" with notifications denied and "Anthropic" with no
    // key were confident lies (2026-07-22 audit).
    private var remindersSummary: String {
        let count = [remindMeals, remindWater, remindStreak].count(where: { $0 })
        if count == 0 { return "Off" }
        return notificationsDenied ? "\(count) on — blocked" : "\(count) on"
    }

    private var onlineDatabaseSummary: String {
        guard onlineLookups else { return "Off" }
        let name: String
        switch textSearchSource {
        case SharedStore.textSearchSourceFDC: name = "USDA FDC"
        case SharedStore.textSearchSourceBoth: name = "Both"
        default: return "OpenFoodFacts"
        }
        // FDC-backed sources are dead without the user's key.
        return SharedStore.isPlausibleFDCKey(SharedStore.fdcAPIKey) ? name : "\(name) — no key"
    }

    private var aiSummary: String {
        guard aiEnabled else { return "Off" }
        let name = AIProviderSettings.selected.displayName
        return FoodIntelligence.isAvailable ? name : "\(name) — not set up"
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

    // The sodium limit lives inside its tracked-metric section; water
    // keeps its own — serving size is about the log buttons, and the
    // goal rides with it. Placed right under the tracked metrics: the
    // water slot's caption points here for its target.
    /// Resolved display units (raw setting + region fallback).
    private var resolvedWaterUnit: WaterUnit { WaterUnit.resolve(waterUnit) }
    private var resolvedSodiumUnit: SodiumUnit { SodiumUnit.resolve(sodiumUnit) }

    /// "12 oz" / "355 mL" — the water rows' converted readout.
    private func waterAmountText(_ oz: Double) -> String {
        let unit = resolvedWaterUnit
        return "\(unit.fromOz(oz).formatted(.number.precision(.fractionLength(0)))) \(unit.symbol)"
    }

    /// Metrics and Water behind rows too (the user, 2026-07-22) — the
    /// summaries say what's tracked and the goal, so the main screen
    /// still answers at a glance.
    private var trackingSection: some View {
        Section {
            NavigationLink {
                MetricsSettingsScreen()
            } label: {
                LabeledContent("Metrics") { Text(metricsSummary) }
            }
            NavigationLink {
                WaterSettingsScreen()
            } label: {
                LabeledContent("Water") { Text(waterAmountText(waterGoalOz)) }
            }
        }
    }

    private var metricsSummary: String {
        let names = [1, 2].compactMap { slotNutrient($0)?.displayName(sodium: resolvedSodiumUnit) }
        return names.isEmpty ? "Off" : names.joined(separator: " · ")
    }

    // Its own property: inlining this pushed the Form past what the
    // type-checker will solve in reasonable time.
    private var dataSection: some View {
        Section {
            // Outcomes toast, like the same operations do from Foods
            // and the Log sheet — this screen used a third style
            // (sticky inline text).
            Button("Export Food Library…", systemImage: "square.and.arrow.up") {
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
            Button("Import Food Library…", systemImage: "square.and.arrow.down") {
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
            Text("These actions can't be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                // GitHub is the origin (2026-07-16, was the Forgejo
                // mirror's face) and hosts the docs site.
                Link("https://github.com/ecliptik/onigiri",
                     destination: URL(string: "https://github.com/ecliptik/onigiri")!)
                // The long-form docs, one tap from where questions
                // arise (the user, 2026-07-20).
                Text("[User Guide](https://github.com/ecliptik/onigiri/wiki/User-Guide) · [Privacy Policy](https://ecliptik.github.io/onigiri/privacy/)")
                    .padding(.top, 6)
                // ODbL requires attribution for Open Food Facts data;
                // FDC is public domain but deserves the credit.
                Text("Food data from [Open Food Facts](https://world.openfoodfacts.org) (ODbL) and [USDA FoodData Central](https://fdc.nal.usda.gov).")
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                // Budgets and projections are arithmetic over Health
                // data, not medicine — say so where the user can read it.
                Text("Calorie budgets and weight projections are informational estimates, not medical advice.")
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    /// The AI secrets as Settings found them (the Keychain sits outside
    /// the defaults snapshot) — Cancel and resets restore/clear by hand,
    /// mirroring the FDC key.
    @State private var aiSecretsAtOpen: [String: String] = [
        AIProviderSettings.anthropicKeyAccount: AIProviderSettings.anthropicAPIKey,
        AIProviderSettings.openAIKeyAccount: AIProviderSettings.openAIAPIKey,
        AIProviderSettings.localTokenAccount: AIProviderSettings.localAIToken,
    ]

    private static let aiSecretAccounts = [
        AIProviderSettings.anthropicKeyAccount,
        AIProviderSettings.openAIKeyAccount,
        AIProviderSettings.localTokenAccount,
    ]

    private func clearAISecrets() {
        for account in Self.aiSecretAccounts {
            AIProviderSettings.saveSecret("", account: account)
        }
        aiSecretsAtOpen = Self.aiSecretAccounts.reduce(into: [:]) { $0[$1] = "" }
        // Draft/test state lives in AISettingsScreen — a fresh push
        // re-reads the (now empty) Keychain slots.
    }

    /// The preference values as the sheet found them (missing key =
    /// was unset). Cancel writes these back. Mechanics live in the kit
    /// (PreferenceSnapshot, unit-tested); the key list is
    /// SharedStore.settingsSweepKeys, kept beside the key definitions.
    @State private var entrySnapshot: [String: Any] = [:]

    private static func captureSnapshot() -> [String: Any] {
        PreferenceSnapshot.capture(keys: SharedStore.settingsSweepKeys, from: SharedStore.defaults)
    }

    /// Anything changed since the sheet opened? Drives the swipe gate
    /// and the Cancel confirmation. Defaults reads are in-memory-cached
    /// (cheap per render); the Keychain-backed secrets are deliberately
    /// NOT polled here — a key-only edit can still swipe away, which
    /// errs on the KEEP side (nothing is lost; Cancel still catches it
    /// at tap time via the same snapshot restore).
    private var hasSessionEdits: Bool {
        guard !entrySnapshot.isEmpty else { return false }
        return PreferenceSnapshot.differs(
            from: entrySnapshot, keys: SharedStore.settingsSweepKeys, in: SharedStore.defaults
        )
    }

    /// The permission-banner inputs, shared by the open-time task and
    /// the foreground re-check.
    private func refreshDenialStates() async {
        let status = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
        let denied: Bool = status == .denied
        let anyReminderOn: Bool = remindMeals || remindWater || remindStreak
        notificationsDenied = denied && anyReminderOn
        healthWriteDenied = HealthKitService().sharingDenied()
    }

    private func revertToEntrySnapshot() {
        // A pending custom-icon task must not write after the discard.
        pendingCustomIconTask?.cancel()
        PreferenceSnapshot.restore(
            entrySnapshot, keys: SharedStore.settingsSweepKeys, to: SharedStore.defaults
        )
        // The FDC key lives in the Keychain, outside the defaults
        // snapshot — restore it to what Settings opened with by hand.
        // (Key-field drafts live in the subscreens and re-read storage
        // on each push, so no hand-mirroring here.)
        SharedStore.saveFDCAPIKey(fdcKeyAtOpen)
        // Same for the AI secrets (one Keychain slot per provider).
        for (account, value) in aiSecretsAtOpen {
            AIProviderSettings.saveSecret(value, account: account)
        }
        ReminderScheduler.shared.replan()
        PhoneSyncService.shared.push(from: context)
    }

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
            // The domain wipe doesn't reach the Keychain — clear the
            // FDC key and the AI provider secrets too.
            SharedStore.saveFDCAPIKey("")
            clearAISecrets()
        }
        // Reminders replan off the (possibly cleared) toggles; the push
        // rebuilds the watch mirror and reloads widgets.
        ReminderScheduler.shared.replan()
        PhoneSyncService.shared.push(from: context)
        // A reset is committed, not a pending edit — Cancel after one
        // must not resurrect pre-reset settings over wiped data.
        entrySnapshot = Self.captureSnapshot()
        fdcKeyAtOpen = SharedStore.fdcAPIKey
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
        PreferenceSnapshot.clear(keys: SharedStore.settingsSweepKeys, in: SharedStore.defaults)
        // The FDC key and AI secrets are in the Keychain, not the
        // defaults list.
        SharedStore.saveFDCAPIKey("")
        clearAISecrets()
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
            // Stored AND guarded (2026-07-22 audit): unguarded, the
            // deferred write clobbered a different icon picked inside the
            // window, and an orphaned task could write to storage after
            // Cancel had already dismissed the sheet.
            pendingCustomIconTask?.cancel()
            pendingCustomIconTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, currentIcon(slot) == "custom" else { return }
                setIcon(slot, to: old)
                customIconSlot = slot
            }
        } else {
            PhoneSyncService.shared.push(from: context)
        }
    }

    /// The slot's stored value right now — the deferred custom-icon
    /// write's staleness guard.
    private func currentIcon(_ slot: IconSlot) -> String {
        switch slot {
        case .food: foodIcon
        case .water: waterIcon
        case .reward: rewardIcon
        case .metric1: trackedMetric1Icon
        case .metric2: trackedMetric2Icon
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

    /// The slot's nutrient; nil when set to None (the slot is off).
    private func slotNutrient(_ slot: Int) -> TrackedNutrient? {
        let raw = slot == 1 ? trackedMetric1 : trackedMetric2
        if raw == SharedStore.trackedMetricNone { return nil }
        return TrackedNutrient(key: raw) ?? (slot == 1 ? .sodium : .water)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Front and center (the user, 2026-07-20): the privacy
                // story is the app's spine — one row, first thing.
                Section {
                    Link(destination: URL(string: "https://ecliptik.github.io/onigiri/privacy/")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
                // Only when write access is denied: every log fails with
                // an opaque toast otherwise, and iOS can't deep-link the
                // Health sharing pane — instructions are the recovery.
                if healthWriteDenied {
                    Section("Apple Health") {
                        VStack(alignment: .leading, spacing: 4) {
                            WarningFootnote("Health access is off — logging can't save.")
                            Text("Turn it on in the Health app: Profile → Apps → Onigiri.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Config rows lead (the user, 2026-07-22), tracking
                // rows next; only Untracked days stays inline.
                configSection

                trackingSection

                dataSection

                resetSection
            }
            .compactSections()
            .riceCanvas()
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
            // A moved time reschedules everything pending. One observer
            // over the bundle — five stacked onChanges blew the
            // type-checker budget for the whole modifier chain.
            .onChange(of: [
                remindMealsMinute, remindStreakMinute,
                remindWaterMinute1, remindWaterMinute2, remindWaterMinute3,
            ]) { ReminderScheduler.shared.replan() }
            .task { await refreshDenialStates() }
            // Re-check when the user returns from the system Settings /
            // Health round trip this screen's own banners send them on —
            // a one-shot check left the banner stale after they fixed it
            // (2026-07-22 audit; TodayModel already re-checks the same way).
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshDenialStates() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Settings applies as you go; Cancel rewinds every
                    // preference to how the sheet found it. Resets are
                    // exempt — they re-baseline the snapshot (Cancel
                    // must not half-resurrect a wiped install). With
                    // session edits pending, Cancel confirms first — a
                    // silent ~30-key rewind (including tested API keys)
                    // was the audit's headline trap.
                    Button("Cancel") {
                        if hasSessionEdits {
                            confirmDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            // The forms' discard grammar (MealForm/FoodForm): edits block
            // the swipe so every exit is an explicit Done or a confirmed
            // discard — swipe-keeps vs Cancel-discards silently disagreeing
            // was the other half of the trap.
            .interactiveDismissDisabled(hasSessionEdits)
            .alert("Discard changes?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) {
                    revertToEntrySnapshot()
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Every change made in Settings since it opened goes back to how it was.")
            }
            .onAppear {
                if entrySnapshot.isEmpty {
                    entrySnapshot = Self.captureSnapshot()
                    fdcKeyAtOpen = SharedStore.fdcAPIKey
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
                    ToastCenter.shared.show("Food Library exported ✓")
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
        // The revealed-key re-mask (2026-07-20 audit) moved into the
        // Online Database and AI subscreens with their reveal toggles —
        // a key can only be revealed while its screen is mounted, and
        // each screen watches scenePhase itself.
    }
}

// MARK: - Pushed subscreens

/// Appearance choices, one push off the main screen. Writes land on the
/// shared defaults keys; SettingsView's always-mounted observers handle
/// the icon mirroring, emoji prompt, and watch sync.
private struct AppearanceSettingsScreen: View {
    @AppStorage(SharedStore.foodIconKey, store: SharedStore.defaults) private var foodIcon = "sfFork"
    @AppStorage(SharedStore.rewardIconKey, store: SharedStore.defaults) private var rewardIcon = "onigiri"
    @AppStorage(SharedStore.balanceStyleKey, store: SharedStore.defaults) private var balanceStyle = "remaining"
    @AppStorage(SharedStore.energyStatsStyleKey, store: SharedStore.defaults) private var energyStatsStyle = "cards"
    @AppStorage(SharedStore.progressGaugesKey, store: SharedStore.defaults) private var progressGauges = false

    var body: some View {
        Form {
            Section {
                // navigationLink style: menu pickers strip both image
                // attachments and icon colors from their rows; a pushed
                // list renders real SwiftUI rows — true colors, aligned
                // icon column.
                Picker("Food icon", selection: $foodIcon) {
                    ForEach(SettingsIcons.foodOptions, id: \.tag) { option in
                        HStack(spacing: 10) {
                            FoodIconView(raw: option.tag)
                                .frame(width: 28)
                            Text(option.name)
                        }
                        .tag(option.tag)
                    }
                    SettingsIcons.customRows(current: foodIcon)
                }
                .pickerStyle(.navigationLink)
                // The water icon lives in the Water section — every water
                // knob in one place (the user).
                Picker("Goal badge", selection: $rewardIcon) {
                    ForEach(SettingsIcons.rewardOptions, id: \.tag) { option in
                        HStack(spacing: 10) {
                            Text(SharedStore.rewardEmoji(for: option.tag))
                                .frame(width: 28)
                            Text(option.name)
                        }
                        .tag(option.tag)
                    }
                    SettingsIcons.customRows(current: rewardIcon)
                }
                .pickerStyle(.navigationLink)
                // Also cycled by tapping the Today headline — same setting,
                // so the picker and the tap stay in agreement.
                Picker("Calorie display", selection: $balanceStyle) {
                    Text("kcal left").tag("remaining")
                    Text("kcal balance").tag("balance")
                    Text("kcal eaten").tag("eaten")
                    Text("kcal budget").tag("budget")
                }
                // "Compact" trades the Intake/Active/Resting cards for
                // Burned/Eaten beside the headline — more room for the log.
                Picker("Energy stats", selection: $energyStatsStyle) {
                    Text("Cards").tag("cards")
                    Text("Beside balance").tag("compact")
                }
                Toggle("Progress gauges", isOn: $progressGauges)
            }
        }
        .compactSections()
        .riceCanvas()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// All opt-in; permission is requested the first time a toggle turns
/// on, never at launch. The denied banner's state lives on SettingsView
/// (its open-time check populates it) and rides in as a binding.
private struct RemindersSettingsScreen: View {
    @Binding var notificationsDenied: Bool
    @AppStorage(SharedStore.remindMealsKey, store: SharedStore.defaults) private var remindMeals = false
    @AppStorage(SharedStore.remindWaterKey, store: SharedStore.defaults) private var remindWater = false
    @AppStorage(SharedStore.remindStreakKey, store: SharedStore.defaults) private var remindStreak = false
    // Reminder times (minutes since midnight); defaults mirror
    // ReminderPlanner.Times so an untouched install schedules exactly
    // the original fixed times.
    @AppStorage(SharedStore.remindMealsMinuteKey, store: SharedStore.defaults) private var remindMealsMinute = 14 * 60
    @AppStorage(SharedStore.remindStreakMinuteKey, store: SharedStore.defaults) private var remindStreakMinute = 20 * 60
    @AppStorage(SharedStore.remindWaterMinute1Key, store: SharedStore.defaults) private var remindWaterMinute1 = 11 * 60
    @AppStorage(SharedStore.remindWaterMinute2Key, store: SharedStore.defaults) private var remindWaterMinute2 = 15 * 60
    @AppStorage(SharedStore.remindWaterMinute3Key, store: SharedStore.defaults) private var remindWaterMinute3 = 19 * 60

    var body: some View {
        Form {
            Section {
                Toggle("Not logged by \(timeLabel(remindMealsMinute))", isOn: $remindMeals)
                if remindMeals {
                    ReminderTimeRow(label: "Remind at", minute: $remindMealsMinute)
                }
                Toggle("Water pacing", isOn: $remindWater)
                if remindWater {
                    ReminderTimeRow(label: "First check-in", minute: $remindWaterMinute1)
                    ReminderTimeRow(label: "Second check-in", minute: $remindWaterMinute2)
                    ReminderTimeRow(label: "Last check-in", minute: $remindWaterMinute3)
                }
                Toggle("Streak about to lapse", isOn: $remindStreak)
                if remindStreak {
                    ReminderTimeRow(label: "Check at", minute: $remindStreakMinute)
                }
                if notificationsDenied {
                    VStack(alignment: .leading, spacing: 4) {
                        WarningFootnote("Notifications are off for Onigiri — reminders won't appear.")
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
                    Task {
                        if await ReminderScheduler.shared.preview() {
                            ToastCenter.shared.show("Previews on the way ✓")
                        } else {
                            // Same orange door the toggles use — silence was
                            // the old behavior's bug.
                            notificationsDenied = true
                        }
                    }
                }
                #endif
            } footer: {
                // The times live in the rows now; only what they can't say
                // rides here.
                Text("Water check-ins nudge only while you're behind an even pace toward the Water section's goal; the streak check warns before a streak lapses at midnight.")
            }
        }
        .compactSections()
        .riceCanvas()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "2:00 PM" for a minutes-since-midnight value (toggle labels).
    private func timeLabel(_ minute: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Where text search looks things up. Barcode scans stay on
/// OpenFoodFacts either way; FDC needs the user's own api.data.gov
/// key (device-local, never synced — see PLAN-1.7). Draft/test state
/// lives here and re-reads storage on every push, so Cancel and the
/// resets (which run on SettingsView) need no hand-mirroring.
private struct OnlineDatabaseSettingsScreen: View {
    /// Re-masks a revealed key on backgrounding — defense in depth
    /// beside the window-level PrivacyShield (2026-07-20 audit); the
    /// observer rides with the reveal toggle now.
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SharedStore.onlineLookupsKey, store: SharedStore.defaults) private var onlineLookups = false
    @AppStorage(SharedStore.textSearchSourceKey, store: SharedStore.defaults) private var textSearchSource = SharedStore.textSearchSourceOFF
    /// What the key field shows; only plausible keys flow to storage
    /// (the Keychain — see SharedStore.saveFDCAPIKey).
    @State private var fdcAPIKeyDraft = SharedStore.fdcAPIKey
    /// The "Test Key" round-trip's verdict; editing the key voids it.
    @State private var fdcKeyTest = FDCKeyTest.idle
    /// The key masks to dots by default; the eye toggle reveals it.
    @State private var showFDCKey = false

    var body: some View {
        Form {
            Section {
                // Off by default, like AI (the user, 2026-07-20): nothing
                // leaves the device until it's switched on. OFF = search is
                // library-only and the scanner reads labels only.
                Toggle("Online lookups", isOn: $onlineLookups)
                if onlineLookups {
                Picker("Source", selection: $textSearchSource) {
                    Text("OpenFoodFacts").tag(SharedStore.textSearchSourceOFF)
                    Text("USDA FoodData Central").tag(SharedStore.textSearchSourceFDC)
                    Text("Both").tag(SharedStore.textSearchSourceBoth)
                }
                if textSearchSource != SharedStore.textSearchSourceOFF {
                    // A plain TextField keeps the standard long-press
                    // paste. It edits a DRAFT: only a plausible key (or a
                    // deliberate clear) reaches storage, so a mis-paste
                    // can't silently break search.
                    HStack {
                        // Masked by default (it's a credential), revealed by
                        // the eye toggle. Both edit the same draft, so paste
                        // and the plausibility gate work either way.
                        Group {
                            if showFDCKey {
                                TextField("API key", text: $fdcAPIKeyDraft)
                            } else {
                                SecureField("API key", text: $fdcAPIKeyDraft)
                            }
                        }
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                        .font(.callout.monospaced())
                        .onChange(of: fdcAPIKeyDraft) { _, raw in
                            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            if key.isEmpty || SharedStore.isPlausibleFDCKey(key) {
                                SharedStore.saveFDCAPIKey(key)
                            }
                            // A different key means the last verdict is
                            // about someone else.
                            fdcKeyTest = .idle
                        }
                        Button {
                            showFDCKey.toggle()
                        } label: {
                            Image(systemName: showFDCKey ? "eye.slash" : "eye")
                                // HIG 44 pt tap target via hit area only —
                                // the negative inset must not move layout.
                                .contentShape(.interaction, Rectangle().inset(by: -14))
                                .contentShape(.accessibility, Rectangle().inset(by: -14))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(showFDCKey ? "Hide API key" : "Show API key")
                    }
                    let draft = fdcAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if draft.isEmpty {
                        WarningFootnote("An API key is required to use the USDA FoodData Central, go to [fdc.nal.usda.gov/api-guide](https://fdc.nal.usda.gov/api-guide) to request a key")
                    } else if !SharedStore.isPlausibleFDCKey(draft) {
                        WarningFootnote("API keys are 40 letters and digits — this one is \(draft.count) and won't be saved.")
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
                            Label {
                                Text("Success").foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        case .failure(let reason):
                            WarningFootnote(verbatim: reason)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                }
            } footer: {
                if onlineLookups {
                    Text("[OpenFoodFacts](https://world.openfoodfacts.org) is always used for barcode scanning")
                } else {
                    Text("Online lookups are off — searches use your Food Library only, and the scanner reads nutrition labels on-device. Everything remains local to your device.")
                }
            }
        }
        .compactSections()
        .riceCanvas()
        .navigationTitle("Online Database")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                showFDCKey = false
            }
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
                verdict = .failure("USDA rejected this key")
            } catch let error as FoodDataCentralError where error.isBusy {
                verdict = .failure("USDA is busy — try again in a minute")
            } catch {
                verdict = .failure("Couldn't reach USDA")
            }
            if fdcAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines) == key {
                fdcKeyTest = verdict
                announce(verdict)
            }
        }
    }
}

/// The visual verdict swap says nothing to VoiceOver — announce it, the
/// way ToastCenter already does for every other Settings outcome.
private func announce(_ verdict: FDCKeyTest) {
    switch verdict {
    case .success:
        AccessibilityNotification.Announcement("Success").post()
    case .failure(let reason):
        AccessibilityNotification.Announcement(reason).post()
    case .idle, .testing:
        break
    }
}

/// Which engine answers the AI features (PLAN-byo-ai): On-Device
/// (Apple Intelligence, the default) or the user's own Anthropic /
/// OpenAI / local OpenAI-compatible server. Every AI affordance in
/// the app follows FoodIntelligence.isAvailable, so configuring a
/// provider here lights them up — including on devices without
/// Apple Intelligence.
private struct AISettingsScreen: View {
    /// Re-masks a revealed key on backgrounding (2026-07-20 audit).
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AIProviderSettings.enabledKey, store: SharedStore.defaults) private var aiEnabled = false
    @AppStorage(AIProviderSettings.providerKey, store: SharedStore.defaults) private var aiProvider = AIProvider.onDevice.rawValue
    @AppStorage(AIProviderSettings.anthropicModelKey, store: SharedStore.defaults) private var aiAnthropicModel = ""
    @AppStorage(AIProviderSettings.openAIModelKey, store: SharedStore.defaults) private var aiOpenAIModel = ""
    @AppStorage(AIProviderSettings.localModelKey, store: SharedStore.defaults) private var aiLocalModel = ""
    @AppStorage(AIProviderSettings.localBaseURLKey, store: SharedStore.defaults) private var aiLocalBaseURL = ""
    @AppStorage(AIProviderSettings.localVisionKey, store: SharedStore.defaults) private var aiLocalVision = false
    /// The SELECTED provider's secret, drafted like the FDC key —
    /// reloaded when the picker moves (each provider keeps its own
    /// Keychain slot, so switching never clobbers another's key).
    @State private var aiKeyDraft = ""
    @State private var showAIKey = false
    /// Test-connection verdict; editing anything voids it.
    @State private var aiTest = FDCKeyTest.idle

    var body: some View {
        Form {
            Section {
                // The master switch leads: AI is entirely optional, and OFF
                // hides every AI affordance app-wide (the user).
                Toggle("AI features", isOn: $aiEnabled)
                if aiEnabled {
                Picker("Engine", selection: $aiProvider) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .onChange(of: aiProvider) { _, _ in
                    aiKeyDraft = aiStoredSecret
                    aiTest = .idle
                }
                .onAppear { aiKeyDraft = aiStoredSecret }
                switch AIProviderSettings.selected {
                case .onDevice:
                    if !FoodIntelligence.onDeviceAvailable {
                        WarningFootnote("Apple Intelligence isn't available on this iPhone — AI features are unavailable. Pick a provider above to bring your own.")
                    }
                case .anthropic:
                    // The on-device case always said WHY nothing works;
                    // the remote cases silently hid every AI affordance
                    // until a key arrived (2026-07-22 audit).
                    if !AIProviderSettings.selectedRemoteIsConfigured {
                        WarningFootnote("Enter an API key below to turn AI features on.")
                    }
                    aiKeyField("API key")
                    aiModelField($aiAnthropicModel, prompt: AIProviderSettings.defaultAnthropicModel)
                case .openAI:
                    if !AIProviderSettings.selectedRemoteIsConfigured {
                        WarningFootnote("Enter an API key below to turn AI features on.")
                    }
                    aiKeyField("API key")
                    aiModelField($aiOpenAIModel, prompt: AIProviderSettings.defaultOpenAIModel)
                case .local:
                    if !AIProviderSettings.selectedRemoteIsConfigured {
                        WarningFootnote("Enter a server and model below to turn AI features on.")
                    }
                    LabeledContent("Server") {
                        // verbatim: a literal prompt goes through markdown,
                        // which auto-links the URL and renders it blue.
                        TextField("Server", text: $aiLocalBaseURL, prompt: Text(verbatim: "http://192.168.1.20:11434/v1"))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .font(.callout.monospaced())
                            .multilineTextAlignment(.trailing)
                            .onChange(of: aiLocalBaseURL) { _, _ in aiTest = .idle }
                    }
                    aiModelField($aiLocalModel, prompt: "gemma3")
                    aiKeyField("Token (optional)")
                    // The photo path needs the user's word — servers don't
                    // advertise vision. Off = Identify Food sends classifier
                    // labels as text instead of the photo.
                    Toggle("Model accepts photos", isOn: $aiLocalVision)
                }
                if AIProviderSettings.selected != .onDevice {
                    HStack {
                        Button("Test connection") { testAIConnection() }
                            .disabled(!AIProviderSettings.selectedRemoteIsConfigured || aiTest == .testing)
                        Spacer()
                        switch aiTest {
                        case .idle:
                            EmptyView()
                        case .testing:
                            ProgressView()
                        case .success:
                            Label {
                                Text("Success").foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        case .failure(let reason):
                            WarningFootnote(verbatim: reason)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                }
            } footer: {
                // ONE tight line per state — the provider descriptions are
                // the user's copy (kit providerDescription) — plus the two
                // doors to the long-form story (the user, 2026-07-20).
                VStack(alignment: .leading, spacing: 6) {
                    if !aiEnabled {
                        Text("All AI features are off — estimates, label reading, and Identify Food are hidden.")
                    } else {
                        Text(AIProviderSettings.selected.providerDescription)
                    }
                    // Deep links to each doc's AI section specifically
                    // (the user) — the general doors live in the colophon.
                    Text("[User Guide](https://github.com/ecliptik/onigiri/wiki/User-Guide#ai-features) · [Privacy Policy](https://ecliptik.github.io/onigiri/privacy/#ai-features-optional)")
                }
            }
        }
        .compactSections()
        .riceCanvas()
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                showAIKey = false
            }
        }
    }

    /// Which Keychain slot the key field edits for the selected
    /// provider; nil for On-Device (no field shows).
    private var aiSecretAccount: String? {
        switch AIProviderSettings.selected {
        case .onDevice: nil
        case .anthropic: AIProviderSettings.anthropicKeyAccount
        case .openAI: AIProviderSettings.openAIKeyAccount
        case .local: AIProviderSettings.localTokenAccount
        }
    }

    private var aiStoredSecret: String {
        switch AIProviderSettings.selected {
        case .onDevice: ""
        case .anthropic: AIProviderSettings.anthropicAPIKey
        case .openAI: AIProviderSettings.openAIAPIKey
        case .local: AIProviderSettings.localAIToken
        }
    }

    /// Masked-by-default secret field, the FDC key's grammar: plain
    /// TextField behind an eye toggle, edits a draft, saves as typed
    /// (no shape gate — provider key formats vary and change).
    private func aiKeyField(_ title: String) -> some View {
        HStack {
            Group {
                if showAIKey {
                    TextField(title, text: $aiKeyDraft)
                } else {
                    SecureField(title, text: $aiKeyDraft)
                }
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            .font(.callout.monospaced())
            .onChange(of: aiKeyDraft) { _, raw in
                if let account = aiSecretAccount {
                    AIProviderSettings.saveSecret(raw, account: account)
                }
                aiTest = .idle
            }
            Button {
                showAIKey.toggle()
            } label: {
                Image(systemName: showAIKey ? "eye.slash" : "eye")
                    // HIG 44 pt tap target via hit area only — the
                    // negative inset must not move layout.
                    .contentShape(.interaction, Rectangle().inset(by: -14))
                    .contentShape(.accessibility, Rectangle().inset(by: -14))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(showAIKey ? "Hide key" : "Show key")
        }
    }

    private func aiModelField(_ binding: Binding<String>, prompt: String) -> some View {
        LabeledContent("Model") {
            TextField("Model", text: binding, prompt: Text(prompt))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.callout.monospaced())
                .multilineTextAlignment(.trailing)
        }
    }

    /// One cheapest-possible round trip through the configured provider
    /// — answers "does this key/server actually work?" at entry time,
    /// so the first failed estimate isn't the messenger.
    private func testAIConnection() {
        aiTest = .testing
        let provider = AIProviderSettings.selected
        let system = #"Reply with ONLY the JSON object {"ok":true}."#
        Task {
            var verdict: FDCKeyTest
            do {
                switch provider {
                case .onDevice:
                    return
                case .anthropic:
                    _ = try await AnthropicClient.completeJSON(
                        apiKey: AIProviderSettings.anthropicAPIKey,
                        model: AIProviderSettings.anthropicModel,
                        system: system, user: "ping", maxTokens: 24)
                case .openAI:
                    _ = try await OpenAICompatibleClient.completeJSON(
                        baseURL: OpenAICompatibleClient.openAIBaseURL,
                        apiKey: AIProviderSettings.openAIAPIKey,
                        model: AIProviderSettings.openAIModel,
                        system: system, user: "ping", maxTokens: 24)
                case .local:
                    guard let base = AIProviderSettings.localBaseURL else {
                        throw AIChatError.badURL
                    }
                    _ = try await OpenAICompatibleClient.completeJSON(
                        baseURL: base,
                        apiKey: AIProviderSettings.localAIToken,
                        model: AIProviderSettings.localModel,
                        system: system, user: "ping", maxTokens: 24)
                }
                verdict = .success
            } catch let error as AIChatError {
                verdict = .failure(error.errorDescription ?? "Connection failed")
            } catch {
                verdict = .failure("Couldn't reach the server")
            }
            if AIProviderSettings.selected == provider {
                aiTest = verdict
                announce(verdict)
            }
        }
    }
}

/// Today's two tracked-metric slots: metric (or None), type, target,
/// icon. Sodium and water targets stay on their long-standing keys
/// (nutrition detail, calendar, and reminders read those). Writes land
/// on the shared keys; SettingsView's root observers handle the watch
/// sync and the custom-emoji prompt.
private struct MetricsSettingsScreen: View {
    @AppStorage(SharedStore.trackedMetric1Key, store: SharedStore.defaults) private var trackedMetric1 = "sodium"
    @AppStorage(SharedStore.trackedMetric1ModeKey, store: SharedStore.defaults) private var trackedMetric1Mode = ""
    @AppStorage(SharedStore.trackedMetric1TargetKey, store: SharedStore.defaults) private var trackedMetric1Target = 0.0
    @AppStorage(SharedStore.trackedMetric1IconKey, store: SharedStore.defaults) private var trackedMetric1Icon = ""
    @AppStorage(SharedStore.trackedMetric2Key, store: SharedStore.defaults) private var trackedMetric2 = "water"
    @AppStorage(SharedStore.trackedMetric2ModeKey, store: SharedStore.defaults) private var trackedMetric2Mode = ""
    @AppStorage(SharedStore.trackedMetric2TargetKey, store: SharedStore.defaults) private var trackedMetric2Target = 0.0
    @AppStorage(SharedStore.trackedMetric2IconKey, store: SharedStore.defaults) private var trackedMetric2Icon = ""
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0
    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults) private var sodiumUnit = SharedStore.unitAutomatic
    @AppStorage(SharedStore.untrackedBelowKey, store: SharedStore.defaults) private var untrackedBelowKcal = 1000.0

    private var resolvedSodiumUnit: SodiumUnit { SodiumUnit.resolve(sodiumUnit) }

    /// The stepper's readout, doubled as its spoken value.
    private var untrackedValueText: String {
        untrackedBelowKcal > 0
            ? "< \(untrackedBelowKcal.formatted(.number.precision(.fractionLength(0)))) kcal"
            : "Off"
    }

    var body: some View {
        Form {
            trackedMetricSection(slot: 1)
            trackedMetricSection(slot: 2)
            // Rehomed from the main screen (the user, 2026-07-22): it's a
            // tracking-behavior knob, and it was the last inline orphan.
            Section {
                Stepper(value: $untrackedBelowKcal, in: 0...2000, step: 100) {
                    LabeledContent("Counts as untracked") {
                        Text(untrackedValueText)
                    }
                }
                .accessibilityLabel("Counts as untracked")
                .accessibilityValue(untrackedValueText)
                Text("Days with less logged break the streak and stay out of the month's totals. 0 turns this off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Untracked days")
            }
        }
        .compactSections()
        .riceCanvas()
        .navigationTitle("Metrics")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The slot's nutrient; nil when set to None (the slot is off).
    private func slotNutrient(_ slot: Int) -> TrackedNutrient? {
        let raw = slot == 1 ? trackedMetric1 : trackedMetric2
        if raw == SharedStore.trackedMetricNone { return nil }
        return TrackedNutrient(key: raw) ?? (slot == 1 ? .sodium : .water)
    }

    /// A None slot shows only the Metric row; water skips Type (always a
    /// goal) and points at Water settings for its target.
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
                // Water skips the row — it's always a goal (SharedStore
                // enforces the same).
                if nutrient != .water {
                    Picker("Type", selection: modeBinding(slot: slot, nutrient: nutrient)) {
                        Text("Limit").tag(TrackedMetricMode.limit.rawValue)
                        Text("Goal").tag(TrackedMetricMode.goal.rawValue)
                    }
                    .pickerStyle(.menu)
                }
                switch nutrient {
                case .sodium:
                    // Generic in presentation; the value stays on the
                    // long-standing sodium-limit key (mg) — salt mode
                    // edits through a converted binding.
                    LabeledContent("Target") {
                        HStack(spacing: 4) {
                            TextField("0", value: sodiumLimitBinding, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                            Text(resolvedSodiumUnit.symbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .water:
                    // A real door, not an inert pointer — the reader is
                    // two screens away from where this text sends them.
                    NavigationLink {
                        WaterSettingsScreen()
                    } label: {
                        Text("See Water settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                // Water's icon is NOT a slot icon: it lives with every
                // other water knob in the Water screen (and drives the
                // log buttons and watch regardless of tracking).
                if nutrient != .water {
                    metricIconPicker(slot: slot, nutrient: nutrient)
                }
            }
        } header: {
            Text(slot == 1 ? "First tracked metric" : "Second tracked metric")
        }
        // Sodium's limit keeps coloring the calendar, day details, and
        // Today's log even when no slot tracks it — keep its knob
        // reachable.
        if slot == 2, !slotTracksSodium {
            Section {
                LabeledContent("\(resolvedSodiumUnit.nutrientName) limit") {
                    HStack(spacing: 4) {
                        TextField("0", value: sodiumLimitBinding, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text(resolvedSodiumUnit.symbol)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Colors \(resolvedSodiumUnit.nutrientName.lowercased()) in the calendar and day details even while untracked.")
            }
        }
    }

    private var slotTracksSodium: Bool {
        slotNutrient(1) == .sodium || slotNutrient(2) == .sodium
    }

    /// The sodium-limit fields edit mg through the display unit — an
    /// identity in mg mode; ×2.5/1000 both ways in salt mode.
    private var sodiumLimitBinding: Binding<Double> {
        Binding(
            get: { resolvedSodiumUnit.fromMg(sodiumLimitMg) },
            set: { sodiumLimitMg = resolvedSodiumUnit.toMg($0) }
        )
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
}

/// Every water knob in one place, one push down: serving size, daily
/// goal, the long-press shortcut, and the app-wide water icon.
private struct WaterSettingsScreen: View {
    @AppStorage(SharedStore.waterServingKey, store: SharedStore.defaults) private var waterServingOz = 12.0
    @AppStorage(SharedStore.waterGoalKey, store: SharedStore.defaults) private var waterGoalOz = 64.0
    @AppStorage(SharedStore.holdToLogWaterKey, store: SharedStore.defaults) private var holdToLogWater = true
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "sfDrop"
    @AppStorage(SharedStore.waterUnitKey, store: SharedStore.defaults) private var waterUnit = SharedStore.unitAutomatic

    private var resolvedWaterUnit: WaterUnit { WaterUnit.resolve(waterUnit) }

    private func waterAmountText(_ oz: Double) -> String {
        let unit = resolvedWaterUnit
        return "\(unit.fromOz(oz).formatted(.number.precision(.fractionLength(0)))) \(unit.symbol)"
    }

    var body: some View {
        Form {
            Section {
                // Steps in round display units: ±2 oz, or ±25 mL in metric
                // mode (stepping the stored oz by twos would read as
                // ±59 mL). Storage stays oz either way.
                Stepper {
                    LabeledContent("Serving size") {
                        Text(waterAmountText(waterServingOz))
                    }
                } onIncrement: {
                    if resolvedWaterUnit == .fluidOunces {
                        waterServingOz = min(40, waterServingOz + 2)
                    } else {
                        // Snap-then-step keeps the readout on round mL;
                        // bounds clamp in mL too (100–1,200 ≈ the oz range)
                        // so the edges don't land on 118/1,183.
                        let ml = (WaterUnit.milliliters.fromOz(waterServingOz) / 25).rounded() * 25
                        waterServingOz = WaterUnit.milliliters.toOz(min(1_200, ml + 25))
                    }
                } onDecrement: {
                    if resolvedWaterUnit == .fluidOunces {
                        waterServingOz = max(4, waterServingOz - 2)
                    } else {
                        let ml = (WaterUnit.milliliters.fromOz(waterServingOz) / 25).rounded() * 25
                        waterServingOz = WaterUnit.milliliters.toOz(max(100, ml - 25))
                    }
                }
                // Explicit value: VoiceOver's adjustable swipes speak the
                // accessibilityValue, not a re-flattened label.
                .accessibilityLabel("Serving size")
                .accessibilityValue(waterAmountText(waterServingOz))
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
                        // Serving-multiple snapping below is oz-space and
                        // unit-agnostic; only this readout converts.
                        Text(waterAmountText(waterGoalOz))
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
                .accessibilityLabel("Daily goal")
                .accessibilityValue(waterAmountText(waterGoalOz))
                // Opt-out (default on) — and the row doubles as the
                // feature's signpost (the user).
                Toggle("Long press + logs water", isOn: $holdToLogWater)
                // The app-wide water icon (Today, log buttons, watch) —
                // here unconditionally: one home for every water setting.
                Picker("Water icon", selection: $waterIcon) {
                    ForEach(SettingsIcons.waterOptions, id: \.tag) { option in
                        HStack(spacing: 10) {
                            WaterIconView(raw: option.tag)
                                .frame(width: 28)
                            Text(option.name)
                        }
                        .tag(option.tag)
                    }
                    SettingsIcons.customRows(current: waterIcon)
                }
                .pickerStyle(.navigationLink)
            }
        }
        .compactSections()
        .riceCanvas()
        .navigationTitle("Water")
        .navigationBarTitleDisplayMode(.inline)
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
