/// An estimate, in the shape the confirm sheet reads. `OnigiriShare`'s
/// extension has no food form, so `ParsedLabel` is the only currency it
/// deals in — moved here from a private extension in `ShareFlow.swift`
/// (health-check audit, 2026-09-14) so the two "empty string → nil"
/// conversions below (`name`, `servingDescription`) are covered by
/// `OnigiriKitTests` instead of living untested in a share extension with
/// no test target of its own.
public extension ScannedProduct {
    var parsedLabel: ParsedLabel {
        var label = ParsedLabel()
        label.name = name.isEmpty ? nil : name
        label.kcal = kcal
        label.sodiumMg = sodiumMg
        label.nutrients = nutrients
        label.servingDescription = servingDescription.isEmpty ? nil : servingDescription
        label.aiGenerated = aiGenerated
        label.warnings = warnings
        return label
    }
}
