import Foundation

/// The one gate every nutrition figure passes before it can reach a form
/// or the log (`plans/PLAN-nutrition-plausibility.md`, Layer 2).
///
/// It exists because the bounds it replaces were scattered and partial:
/// the MODEL paths each carried their own ceilings (sodium ≤ 20,000 mg,
/// kcal ≤ 5,000, macros clamped in `macroNutrients`) while the
/// DETERMINISTIC paths carried one — `kcal < 10_000` — and nothing else.
/// So the engine that was guarded deferred to the engine that was not: a
/// shared product page read 810,400 mg of sodium off a copyright line
/// and every gate in the app was somewhere else (2026-08-16).
///
/// Two severities, because they have earned different behaviour:
///
/// - **Impossible** values are DROPPED, field by field, and the reading
///   survives without them. The galette's 300 kcal was right; only its
///   sodium was nonsense, and throwing away the whole reading would have
///   punished the user for the parser's mistake.
/// - **Suspect** values are KEPT and marked. They are legal — ramen
///   really does carry 4,000 mg of sodium — so the app says "look at
///   this" rather than deciding. That distinction is the whole reason
///   this isn't a single ceiling.
///
/// Every threshold below is calibrated against real food and named in
/// the tests, so raising one means arguing with a bouillon cube rather
/// than with a number.
public enum NutritionPlausibility {
    public enum Field: String, Sendable, Equatable, Codable {
        case energy, sodium, fat, saturatedFat, transFat, cholesterol
        case carbs, fiber, sugar, protein

        public var displayName: String {
            switch self {
            case .energy: "Calories"
            case .sodium: "Sodium"
            case .fat: "Fat"
            case .saturatedFat: "Saturated fat"
            case .transFat: "Trans fat"
            case .cholesterol: "Cholesterol"
            case .carbs: "Carbohydrates"
            case .fiber: "Fiber"
            case .sugar: "Sugar"
            case .protein: "Protein"
            }
        }
    }

    public struct Finding: Sendable, Equatable, Codable {
        public enum Severity: String, Sendable, Equatable, Codable {
            /// Removed: no food can be this, so the figure is a misread.
            case dropped
            /// Kept and marked: legal, but worth a second look.
            case suspect
        }

        public let field: Field
        public let severity: Severity
        /// Said in one line, to a person, with the number in it — this
        /// is what the form and the share sheet show.
        public let reason: String

        public init(field: Field, severity: Severity, reason: String) {
            self.field = field
            self.severity = severity
            self.reason = reason
        }
    }

    /// What survived, and what was said about it.
    public struct Reading: Sendable, Equatable {
        public var kcal: Double?
        public var sodiumMg: Double?
        public var nutrients: NutrientValues
        public var findings: [Finding]

        public var dropped: [Finding] { findings.filter { $0.severity == .dropped } }
        public var suspect: [Finding] { findings.filter { $0.severity == .suspect } }
    }

    // MARK: Calibration

    /// A single serving of anything. The models' own `@Guide` ceiling.
    public static let maxKcal = 5_000.0
    /// Sodium's absolute ceiling per serving. Nothing edible in one
    /// sitting approaches it; the 810,400 mg misread cleared it 40×.
    public static let maxSodiumMg = 20_000.0
    /// Sodium per calorie, for when the serving's WEIGHT is unknown.
    /// Set above the saltiest real foods on purpose — a bouillon cube is
    /// ~200 mg/kcal, soy sauce ~90, a dill pickle ~60 — so this can only
    /// catch arithmetic, never a cuisine. The galette read 2,701.
    public static let maxSodiumMgPerKcal = 250.0
    /// Pure table salt is 39.3% sodium by mass, so no serving can be
    /// more sodium than this fraction of its own weight.
    public static let maxSodiumMassFraction = 0.4
    /// Legal but worth a look: about 1.3× the daily limit in one go.
    public static let suspectSodiumMg = 3_000.0
    /// Absolute per-serving ceilings, mirroring the `@Guide` ranges the
    /// models are held to, so the two engines can't drift apart.
    public static let maxFatG = 500.0
    public static let maxCarbsG = 1_000.0
    public static let maxProteinG = 500.0
    public static let maxFiberG = 300.0
    public static let maxSugarG = 1_000.0
    public static let maxCholesterolMg = 10_000.0
    /// Atwater agreement, generously: alcohol is 7 kcal/g and is not a
    /// tracked field (a margarita is a real log line), and sugar
    /// alcohols break the arithmetic honestly. This flags contradiction,
    /// not imprecision.
    public static let energyTolerance = 0.30
    public static let energyToleranceFloorKcal = 50.0
    /// Slack on the "part cannot exceed its whole" rules: labels round
    /// to the gram, so sugar 12 g inside carbs 11.6 g is rounding, not a
    /// contradiction.
    public static let componentSlackG = 1.0

    // MARK: The gate

    public static func check(
        kcal: Double?,
        sodiumMg: Double?,
        nutrients: NutrientValues,
        servingGrams: Double? = nil
    ) -> Reading {
        var reading = Reading(
            kcal: kcal, sodiumMg: sodiumMg, nutrients: nutrients, findings: [])

        func drop(_ field: Field, _ reason: String) {
            reading.findings.append(Finding(field: field, severity: .dropped, reason: reason))
        }
        func suspect(_ field: Field, _ reason: String) {
            reading.findings.append(Finding(field: field, severity: .suspect, reason: reason))
        }
        func number(_ value: Double, _ digits: Int = 0) -> String {
            value.formatted(.number.precision(.fractionLength(0...digits)))
        }

        // ---- impossible: energy ----
        if let value = reading.kcal, value < 0 || value > maxKcal {
            reading.kcal = nil
            drop(.energy, "\(number(value)) kcal in one serving isn't a food.")
        }

        // ---- impossible: sodium ----
        if let value = reading.sodiumMg {
            if value < 0 || value > maxSodiumMg {
                reading.sodiumMg = nil
                drop(.sodium, "\(number(value)) mg is beyond any real food.")
            } else if let grams = servingGrams, grams > 0,
                      value / 1_000 > grams * maxSodiumMassFraction {
                reading.sodiumMg = nil
                drop(.sodium, """
                    \(number(value)) mg is more sodium than a \
                    \(number(grams)) g serving can weigh.
                    """)
            } else if let energy = reading.kcal, energy > 0,
                      value > energy * maxSodiumMgPerKcal {
                reading.sodiumMg = nil
                drop(.sodium, """
                    \(number(value)) mg beside \(number(energy)) kcal is \
                    \(number(value / energy)) mg per calorie — saltier than salt.
                    """)
            }
        }

        // ---- impossible: a nutrient heavier than its serving, or past
        // its own ceiling ----
        let ceilings: [(Field, WritableKeyPath<NutrientValues, Double?>, Double, String)] = [
            (.fat, \.fatG, maxFatG, "g"),
            (.saturatedFat, \.saturatedFatG, maxFatG, "g"),
            (.transFat, \.transFatG, maxFatG, "g"),
            (.carbs, \.carbsG, maxCarbsG, "g"),
            (.fiber, \.fiberG, maxFiberG, "g"),
            (.sugar, \.sugarG, maxSugarG, "g"),
            (.protein, \.proteinG, maxProteinG, "g"),
            (.cholesterol, \.cholesterolMg, maxCholesterolMg, "mg"),
        ]
        for (field, path, ceiling, unit) in ceilings {
            guard let value = reading.nutrients[keyPath: path] else { continue }
            if value < 0 || value > ceiling {
                reading.nutrients[keyPath: path] = nil
                drop(field, "\(number(value, 1)) \(unit) in one serving isn't a food.")
                continue
            }
            // Grams only: cholesterol is milligrams and never rivals the
            // serving's own weight.
            guard unit == "g", let grams = servingGrams, grams > 0, value > grams else { continue }
            reading.nutrients[keyPath: path] = nil
            drop(field, """
                \(number(value, 1)) g of \(field.displayName.lowercased()) in a \
                \(number(grams)) g serving weighs more than the serving.
                """)
        }

        // ---- suspect: legal, but say so ----
        if let value = reading.sodiumMg, value > suspectSodiumMg {
            suspect(.sodium, "\(number(value)) mg in one serving is unusually high.")
        }

        let n = reading.nutrients
        func exceeds(_ part: Double?, _ whole: Double?) -> Bool {
            guard let part, let whole else { return false }
            return part > whole + componentSlackG
        }
        if exceeds(n.sugarG, n.carbsG) {
            suspect(.sugar, "More sugar than total carbohydrate.")
        }
        if exceeds(n.fiberG, n.carbsG) {
            suspect(.fiber, "More fiber than total carbohydrate.")
        }
        if exceeds(n.saturatedFatG, n.fatG) {
            suspect(.saturatedFat, "More saturated fat than total fat.")
        }
        if exceeds(n.transFatG, n.fatG) {
            suspect(.transFat, "More trans fat than total fat.")
        }

        // ---- suspect: the macros don't add up to the calories ----
        // All three are required: from fat alone the estimate is not
        // wrong, it is meaningless, and flagging on it would cry wolf on
        // every partially-filled label.
        if let energy = reading.kcal, energy > 0,
           let fat = n.fatG, let carbs = n.carbsG, let protein = n.proteinG {
            let fiber = min(n.fiberG ?? 0, carbs)
            let implied = 4 * (carbs - fiber) + 2 * fiber + 9 * fat + 4 * protein
            let allowed = max(energyToleranceFloorKcal, energy * energyTolerance)
            if abs(implied - energy) > allowed {
                suspect(.energy, """
                    The macros work out to about \(number(implied)) kcal, \
                    not \(number(energy)).
                    """)
            }
        }

        return reading
    }

    /// The label-shaped door onto the same gate. Impossible fields come
    /// back empty and every finding rides along in `warnings`, so the
    /// form and the share sheet can say what happened to a number the
    /// user never got to see.
    public static func checked(_ label: ParsedLabel) -> ParsedLabel {
        let reading = check(
            kcal: label.kcal, sodiumMg: label.sodiumMg,
            nutrients: label.nutrients, servingGrams: label.servingGrams)
        var checked = label
        checked.kcal = reading.kcal
        checked.sodiumMg = reading.sodiumMg
        checked.nutrients = reading.nutrients
        checked.warnings = reading.findings
        return checked
    }
}
