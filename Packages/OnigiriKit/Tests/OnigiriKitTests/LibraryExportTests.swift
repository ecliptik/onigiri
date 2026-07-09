import Foundation
import Testing
@testable import OnigiriKit

struct LibraryExportTests {
    @Test func roundTripsThroughJSON() throws {
        let export = LibraryExport(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
            foods: [
                .init(name: "Chicken breast", kcal: 280, sodiumMg: 540, servingDescription: "8 oz", barcode: nil),
                .init(name: "Rice bowl", kcal: 320, sodiumMg: 10, servingDescription: "1 bowl", barcode: "12345678"),
            ],
            meals: [
                .init(name: "Chicken & rice", items: [
                    .init(foodName: "Chicken breast", quantity: 1),
                    .init(foodName: "Rice bowl", quantity: 2),
                ])
            ],
            goal: .init(
                targetWeightLb: 190,
                targetDate: Date(timeIntervalSince1970: 1_805_000_000),
                fallbackCurrentWeightLb: nil
            ),
            water: .init(servingOz: 12, goalOz: 64)
        )
        let data = try export.encoded()
        let decoded = try LibraryExport.decode(data)
        #expect(decoded == export)
    }

    @Test func decodesMinimalDocument() throws {
        let json = """
        {"version":1,"exportedAt":"2026-07-08T00:00:00Z","foods":[],"meals":[],
        "water":{"servingOz":12,"goalOz":64}}
        """
        let decoded = try LibraryExport.decode(Data(json.utf8))
        #expect(decoded.goal == nil)
        #expect(decoded.foods.isEmpty)
    }
}
