import OnigiriKit
import SwiftUI

/// The Units subscreen: one picker per preference, with Automatic
/// labeled by what it currently resolves to on this device. Set-once
/// plumbing, deliberately one row on the main Settings screen (the
/// user, 2026-07-21) — display and entry convert, storage never does.
struct UnitsSettingsView: View {
    @AppStorage(SharedStore.weightUnitKey, store: SharedStore.defaults)
    private var weightUnit = SharedStore.unitAutomatic
    @AppStorage(SharedStore.waterUnitKey, store: SharedStore.defaults)
    private var waterUnit = SharedStore.unitAutomatic
    @AppStorage(SharedStore.sodiumUnitKey, store: SharedStore.defaults)
    private var sodiumUnit = SharedStore.unitAutomatic

    var body: some View {
        Form {
            Section {
                Picker("Weight", selection: $weightUnit) {
                    Text("Automatic — \(WeightUnit.resolve(nil).symbol)")
                        .tag(SharedStore.unitAutomatic)
                    Text("Pounds (lb)").tag(WeightUnit.pounds.rawValue)
                    Text("Kilograms (kg)").tag(WeightUnit.kilograms.rawValue)
                }
                Picker("Water", selection: $waterUnit) {
                    Text("Automatic — \(WaterUnit.resolve(nil).symbol)")
                        .tag(SharedStore.unitAutomatic)
                    Text("Fluid ounces (oz)").tag(WaterUnit.fluidOunces.rawValue)
                    Text("Milliliters (mL)").tag(WaterUnit.milliliters.rawValue)
                }
                // "Salt" is the EU-label framing (salt = sodium × 2.5),
                // not a different measurement — the resolve rule is a
                // region list, not the measurement system.
                Picker("Sodium", selection: $sodiumUnit) {
                    Text("Automatic — \(SodiumUnit.resolve(nil).symbol)")
                        .tag(SharedStore.unitAutomatic)
                    Text("Sodium (mg)").tag(SodiumUnit.milligrams.rawValue)
                    Text("Salt (g)").tag(SodiumUnit.saltGrams.rawValue)
                }
            } footer: {
                Text("Automatic follows your region. Logged data never changes — only how values are shown and entered.")
            }
        }
        .compactSections()
        .riceCanvas()
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { UnitsSettingsView() }
}
