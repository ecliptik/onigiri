import Foundation
import OnigiriKit
import os

private nonisolated(unsafe) let pageLog = Logger(subsystem: "com.ecliptik.Onigiri", category: "shared-page")

/// A shared page that turns out to hold ONE food rather than a menu.
///
/// `MenuTableParser` reads tables, which is what a chain's nutrition
/// guide is. A shop's product page is not: Salt & Straw states its
/// figures in a sentence inside a collapsed accordion — "Three (3)
/// servings per pint. Each serving 2/3 cup. Calories per serving: 300" —
/// so the table parse came back empty and the share failed on a page
/// that plainly had the number on it (the user, 2026-08-16).
///
/// So a document with no table is read the way a SCREENSHOT is, off the
/// same text and through the same cascade: the deterministic parse
/// first, the model only where prose defeats it. Nothing here is new
/// machinery — it is the paste door's path, pointed at a rendered page.
enum SharedPageReader {
    /// The same read, from a page's TEXT rather than its rendering —
    /// which is the only way to reach a figure inside a collapsed
    /// accordion. Lines become observations stacked top to bottom;
    /// prose has no columns, and the label parser only needs order.
    static func singleFood(fromPageText text: String) async -> ParsedLabel? {
        let lines = text.split(separator: "\n").prefix(400)
        guard !lines.isEmpty else { return nil }
        let runs = lines.enumerated().map { index, line in
            LabelObservation(
                text: String(line), x: 0.05,
                y: 0.98 - (Double(index) / Double(max(lines.count, 1))) * 0.96,
                w: 0.9, h: 0.9 / Double(max(lines.count, 1)))
        }
        return await singleFood(from: [runs])
    }

    static func singleFood(from pages: [[LabelObservation]]) async -> ParsedLabel? {
        // The first pages only: a product page states its nutrition near
        // the item, and a long site footer is all navigation.
        let transcript = Array(pages.prefix(3).joined())
        guard !transcript.isEmpty else { return nil }

        var parsed = LabelParser.parse(transcript)
        // Same guard the photo cascade uses: with nothing nutritional in
        // the text there is nothing to read, and a model asked anyway
        // invents.
        if FoodImageReader.mentionsNutrition(transcript), FoodIntelligence.isAvailable {
            let foods = await FoodIntelligence.readNutritionScreenshot(transcript: transcript)
            pageLog.notice("Page read: \(foods.count) food(s) from \(transcript.count) runs")
            // ONE food, because this path exists for a product page. A
            // page listing several is a menu, and the table parser
            // already had its turn.
            if let only = foods.first, foods.count == 1 {
                if parsed.kcal == nil { parsed.kcal = only.parsedLabel.kcal }
                if parsed.name == nil { parsed.name = only.parsedLabel.name }
                if parsed.servingDescription == nil {
                    parsed.servingDescription = only.parsedLabel.servingDescription
                }
                parsed.aiGenerated = parsed.aiGenerated || only.parsedLabel.aiGenerated
                if parsed.sodiumMg == nil { parsed.sodiumMg = only.parsedLabel.sodiumMg }
                let read = only.parsedLabel.nutrients
                if parsed.nutrients.fatG == nil { parsed.nutrients.fatG = read.fatG }
                if parsed.nutrients.saturatedFatG == nil { parsed.nutrients.saturatedFatG = read.saturatedFatG }
                if parsed.nutrients.transFatG == nil { parsed.nutrients.transFatG = read.transFatG }
                if parsed.nutrients.cholesterolMg == nil { parsed.nutrients.cholesterolMg = read.cholesterolMg }
                if parsed.nutrients.carbsG == nil { parsed.nutrients.carbsG = read.carbsG }
                if parsed.nutrients.fiberG == nil { parsed.nutrients.fiberG = read.fiberG }
                if parsed.nutrients.sugarG == nil { parsed.nutrients.sugarG = read.sugarG }
                if parsed.nutrients.proteinG == nil { parsed.nutrients.proteinG = read.proteinG }
            }
        }
        guard parsed.kcal != nil else { return nil }
        return parsed
    }
}
