import SwiftUI
import SwiftData
import OnigiriKit

/// Create or edit a saved food, with barcode scanning to prefill from
/// OpenFoodFacts.
struct FoodFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let food: Food?
    /// Open the barcode scanner immediately (quick-action entry point).
    var startScanning = false

    @State private var name = ""
    @State private var kcal: Double?
    @State private var sodiumMg: Double?
    @State private var serving = ""
    @State private var barcode: String?

    @State private var showScanner = false
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    @FocusState private var numberFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan barcode", systemImage: "barcode.viewfinder")
                    }
                    .disabled(isLookingUp)

                    if isLookingUp {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Looking up product…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let lookupMessage {
                        Text(lookupMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField("Name", text: $name)
                    LabeledContent("Calories (kcal)") {
                        TextField("0", value: $kcal, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($numberFieldFocused)
                    }
                    LabeledContent("Sodium (mg)") {
                        TextField("0", value: $sodiumMg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($numberFieldFocused)
                    }
                    LabeledContent("Serving") {
                        TextField("e.g. 1 cup, 8 oz", text: $serving)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle(food == nil ? "New Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || kcal == nil)
                }
                // Decimal pads have no return key; surface a Done while
                // editing (keyboard-accessory placement is unreliable on
                // iOS 26). The sheet's Cancel/Save stay reachable regardless.
                if numberFieldFocused {
                    ToolbarItem(placement: .principal) {
                        Button {
                            numberFieldFocused = false
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
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $showScanner) {
                BarcodeScannerSheet { code in
                    Task { await lookup(code) }
                }
            }
            .onAppear {
                if let food {
                    name = food.name
                    kcal = food.kcal
                    sodiumMg = food.sodiumMg
                    serving = food.servingDescription
                    barcode = food.barcode
                } else if startScanning {
                    showScanner = true
                }
            }
        }
    }

    private func lookup(_ code: String) async {
        isLookingUp = true
        lookupMessage = nil
        do {
            let product = try await OpenFoodFactsClient().product(barcode: code)
            name = product.name
            kcal = product.kcal
            sodiumMg = product.sodiumMg
            serving = product.servingDescription
            barcode = product.barcode
            if product.kcal == nil {
                lookupMessage = "Found it, but no calorie data — check the label."
            }
        } catch {
            lookupMessage = error.localizedDescription
        }
        isLookingUp = false
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let food {
            food.name = trimmed
            food.kcal = kcal ?? 0
            food.sodiumMg = sodiumMg ?? 0
            food.servingDescription = serving
            food.barcode = barcode
        } else {
            context.insert(Food(
                name: trimmed,
                kcal: kcal ?? 0,
                sodiumMg: sodiumMg ?? 0,
                servingDescription: serving,
                barcode: barcode
            ))
        }
        PhoneSyncService.shared.push(from: context)
        dismiss()
    }
}
