import SwiftUI
import SwiftData
import OnigiriKit

/// App-wide settings: appearance choices and data portability.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SharedStore.waterIconKey, store: SharedStore.defaults) private var waterIcon = "drop"
    @AppStorage(SharedStore.sodiumLimitKey, store: SharedStore.defaults) private var sodiumLimitMg = 2300.0

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: LibraryJSONDocument?
    @State private var transferMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Water icon", selection: $waterIcon) {
                        Text("💧 Droplet").tag("drop")
                        Text("🌊 Great Wave").tag("wave")
                    }
                }

                Section("Sodium") {
                    Stepper(value: $sodiumLimitMg, in: 500...6000, step: 100) {
                        LabeledContent("Daily limit") {
                            Text("\(sodiumLimitMg, format: .number.precision(.fractionLength(0))) mg")
                        }
                    }
                    Text("The FDA guideline is 2,300mg sodium for adults.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Text("Export or import Onigiri Foods, Meals, Goals, and Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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

#Preview {
    SettingsView()
        .modelContainer(for: [Food.self, Meal.self, GoalSettings.self], inMemory: true)
}
