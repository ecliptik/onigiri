import SwiftUI
import SwiftData

/// Create or edit a saved food.
struct FoodFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let food: Food?

    @State private var name = ""
    @State private var kcal: Double?
    @State private var sodiumMg: Double?
    @State private var serving = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Calories (kcal)", value: $kcal, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Sodium (mg)", value: $sodiumMg, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Serving (e.g. 1 cup, 8 oz)", text: $serving)
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
            }
            .onAppear {
                if let food {
                    name = food.name
                    kcal = food.kcal
                    sodiumMg = food.sodiumMg
                    serving = food.servingDescription
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let food {
            food.name = trimmed
            food.kcal = kcal ?? 0
            food.sodiumMg = sodiumMg ?? 0
            food.servingDescription = serving
        } else {
            context.insert(Food(
                name: trimmed,
                kcal: kcal ?? 0,
                sodiumMg: sodiumMg ?? 0,
                servingDescription: serving
            ))
        }
        dismiss()
    }
}
