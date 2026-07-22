import Foundation

/// User-facing display units for body weight, water volume, and sodium.
///
/// Storage never changes: HealthKit samples, SwiftData goals, watch-sync
/// payloads, and backups stay in the canonical units (lb, US fl oz,
/// sodium mg). These types translate at the display/entry boundary only.
/// Each preference stores "auto" (absent reads the same) and resolves
/// against the device locale, so existing installs keep today's units
/// and a metric-region install gets metric out of the box.

public enum WeightUnit: String, CaseIterable, Sendable {
    case pounds = "lb"
    case kilograms = "kg"

    /// kg per international avoirdupois pound (exact).
    public static let kgPerLb = 0.45359237

    /// Explicit raw value, else the locale's convention. US and UK
    /// customarily weigh people in pounds (UK stones stay out of scope);
    /// metric regions in kilograms.
    public static func resolve(_ raw: String?, locale: Locale = .current) -> WeightUnit {
        if let raw, let explicit = WeightUnit(rawValue: raw) { return explicit }
        return locale.measurementSystem == .metric ? .kilograms : .pounds
    }

    public func fromLb(_ lb: Double) -> Double {
        self == .pounds ? lb : lb * Self.kgPerLb
    }

    public func toLb(_ value: Double) -> Double {
        self == .pounds ? value : value / Self.kgPerLb
    }

    /// Row/axis suffix: "lb" / "kg".
    public var symbol: String { rawValue }

    /// Accessibility strings speak the unit out ("pounds").
    public var spoken: String { self == .pounds ? "pounds" : "kilograms" }
}

public enum WaterUnit: String, CaseIterable, Sendable {
    case fluidOunces = "oz"
    case milliliters = "ml"

    /// mL per US fluid ounce — matches HealthKit's `.fluidOunceUS()`.
    public static let mlPerOz = 29.5735295625

    /// US keeps fluid ounces; metric AND UK regions pour in milliliters
    /// (UK drink packaging is metric even where body weight isn't).
    public static func resolve(_ raw: String?, locale: Locale = .current) -> WaterUnit {
        if let raw, let explicit = WaterUnit(rawValue: raw) { return explicit }
        return locale.measurementSystem == .us ? .fluidOunces : .milliliters
    }

    public func fromOz(_ oz: Double) -> Double {
        self == .fluidOunces ? oz : oz * Self.mlPerOz
    }

    public func toOz(_ value: Double) -> Double {
        self == .fluidOunces ? value : value / Self.mlPerOz
    }

    public var symbol: String { self == .fluidOunces ? "oz" : "mL" }

    public func spoken(_ amount: Double) -> String {
        switch self {
        case .fluidOunces: amount == 1 ? "ounce" : "ounces"
        case .milliliters: amount == 1 ? "milliliter" : "milliliters"
        }
    }

    /// "12" / "355" — whole-number readout for X/Y composites.
    public func value(fromOz oz: Double) -> String {
        fromOz(oz).formatted(.number.precision(.fractionLength(0)))
    }

    /// "12 oz" / "355 mL" — the standard converted readout.
    public func text(fromOz oz: Double) -> String {
        "\(value(fromOz: oz)) \(symbol)"
    }
}

public enum SodiumUnit: String, CaseIterable, Sendable {
    case milligrams = "mg"
    case saltGrams = "salt"

    /// EU labeling convention: salt = sodium × 2.5.
    public static let saltPerSodium = 2.5

    /// Salt-in-grams is a labeling convention, not a measurement system —
    /// Australia/NZ are metric yet label sodium in mg. EU + UK + EFTA
    /// read salt; everywhere else reads sodium.
    static let saltRegions: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE",
        "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT",
        "RO", "SK", "SI", "ES", "SE",
        "GB", "IS", "NO", "LI", "CH",
    ]

    public static func resolve(_ raw: String?, locale: Locale = .current) -> SodiumUnit {
        if let raw, let explicit = SodiumUnit(rawValue: raw) { return explicit }
        guard let region = locale.region?.identifier else { return .milligrams }
        return saltRegions.contains(region) ? .saltGrams : .milligrams
    }

    public func fromMg(_ mg: Double) -> Double {
        self == .milligrams ? mg : mg * Self.saltPerSodium / 1000
    }

    public func toMg(_ value: Double) -> Double {
        self == .milligrams ? value : value * 1000 / Self.saltPerSodium
    }

    public var symbol: String { self == .milligrams ? "mg" : "g" }

    /// The unit renames the nutrient: rows read "Salt 3.2 g", not
    /// "Sodium 3.2 g" — grams-of-sodium would be a third thing.
    public var nutrientName: String { self == .milligrams ? "Sodium" : "Salt" }

    /// Whole mg; one decimal for salt (whole grams are too coarse —
    /// 1 g of salt is 400 mg of sodium).
    public var fractionDigits: Int { self == .milligrams ? 0 : 1 }

    public func spoken(_ amount: Double) -> String {
        switch self {
        case .milligrams: amount == 1 ? "milligram" : "milligrams"
        case .saltGrams: amount == 1 ? "gram" : "grams"
        }
    }

    /// "1,450" / "3.6" — the converted number at this unit's precision.
    public func value(fromMg mg: Double) -> String {
        fromMg(mg).formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// "1,450 mg" / "3.6 g" — the standard converted readout.
    public func text(fromMg mg: Double) -> String {
        "\(value(fromMg: mg)) \(symbol)"
    }
}

public extension TrackedNutrient {
    /// Display-unit translation for THIS nutrient under the active unit
    /// preferences: water oz→mL, sodium mg→salt g, all others untouched.
    /// Surfaces that render tracked metrics (Today slots, watch metrics,
    /// widgets, Settings targets) route their numbers through here.
    func displayValue(_ value: Double, water: WaterUnit, sodium: SodiumUnit) -> Double {
        switch self {
        case .water: water.fromOz(value)
        case .sodium: sodium.fromMg(value)
        default: value
        }
    }

    /// Inverse of `displayValue` — what an entry field hands back.
    func canonicalValue(_ display: Double, water: WaterUnit, sodium: SodiumUnit) -> Double {
        switch self {
        case .water: water.toOz(display)
        case .sodium: sodium.toMg(display)
        default: display
        }
    }

    func displayUnitSymbol(water: WaterUnit, sodium: SodiumUnit) -> String {
        switch self {
        case .water: water.symbol
        case .sodium: sodium.symbol
        default: unitSymbol
        }
    }

    /// Salt mode renames sodium ("Salt"); nothing else changes.
    func displayName(sodium: SodiumUnit) -> String {
        self == .sodium ? sodium.nutrientName : displayName
    }

    func displayInlineName(sodium: SodiumUnit) -> String {
        self == .sodium ? sodium.nutrientName.lowercased() : inlineName
    }

    func displayFractionDigits(sodium: SodiumUnit) -> Int {
        self == .sodium ? sodium.fractionDigits : 0
    }

    /// "mg Na" → "g salt"; other nutrients unchanged.
    func displayCaptionUnit(sodium: SodiumUnit) -> String {
        self == .sodium && sodium == .saltGrams ? "g salt" : captionUnit
    }

    /// The full row caption ("340 mg Na" / "0.9 g salt" /
    /// "12 g Protein"): per-item amount in display units, at the
    /// 0...1-decimal style the library and log rows share.
    func captionText(_ amount: Double, sodium: SodiumUnit) -> String {
        let value = self == .sodium ? sodium.fromMg(amount) : amount
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(displayCaptionUnit(sodium: sodium))"
    }
}

public extension SharedStore {
    /// Raw unit-preference settings. "auto" (or absent) = follow the
    /// region. Settings writes these explicitly and the watch sync
    /// always sends them — an absent key would leave a stale explicit
    /// choice alive on the watch after a reset to Automatic.
    static let weightUnitKey = "weightUnit"
    static let waterUnitKey = "waterUnit"
    static let sodiumUnitKey = "sodiumUnit"
    static let unitAutomatic = "auto"

    static var weightUnit: WeightUnit {
        WeightUnit.resolve(defaults.string(forKey: weightUnitKey))
    }

    static var waterUnit: WaterUnit {
        WaterUnit.resolve(defaults.string(forKey: waterUnitKey))
    }

    static var sodiumUnit: SodiumUnit {
        SodiumUnit.resolve(defaults.string(forKey: sodiumUnitKey))
    }
}
