import Foundation

/// Resting (basal) burn for hours the watch wasn't worn.
///
/// Resting energy is only recorded while the Apple Watch is on the wrist —
/// the iPhone doesn't estimate it. Take the watch off at 9pm and Health
/// simply has no basal samples for the rest of the day, so the day's
/// recorded burn is short by however long it sat on the charger. Judging a
/// completed day on that number marks it a failure for taking the watch
/// off (field report 2026-07-30: 2,109 kcal resting one day against 1,562
/// the next — a 547 kcal swing no metabolism produces).
///
/// So unworn hours are filled at the person's OWN average resting rate.
/// Your basal metabolism runs whether or not a watch is watching it; this
/// is arithmetic on a known-continuous process, not a guess.
///
/// **Active burn is deliberately NOT filled.** Movement during unworn
/// hours is genuinely unknown, and inventing active calories would invent
/// a deficit — the one error that would tell someone they hit a goal they
/// missed.
public enum RestingBurnFill {
    /// Below this much coverage a day is not extrapolated. One or two
    /// recorded hours can't distinguish "watch was off" from "barely any
    /// data at all", and scaling a single hour by 24 is fabrication, not
    /// estimation. Such a day keeps exactly what was measured.
    public static let minimumCoveredHours = 4

    /// Resting kcal per worn hour, across a whole window — steadier than
    /// any single day's rate, and still entirely the person's own data.
    /// nil when the window has nothing to learn from.
    public static func hourlyRate(
        totalRestingKcal: Double, totalCoveredHours: Int
    ) -> Double? {
        guard totalCoveredHours > 0, totalRestingKcal > 0 else { return nil }
        return totalRestingKcal / Double(totalCoveredHours)
    }

    /// The day's resting burn with unworn hours filled in. Returns the
    /// recorded value untouched when the day was fully covered, when
    /// coverage is too thin to extrapolate from, or when there's no rate.
    public static func filled(
        recordedRestingKcal: Double,
        coveredHours: Int,
        hourlyRate: Double?,
        dayHours: Int = 24
    ) -> Double {
        guard let hourlyRate, hourlyRate > 0,
              coveredHours >= minimumCoveredHours,
              coveredHours < dayHours
        else { return recordedRestingKcal }
        return recordedRestingKcal + Double(dayHours - coveredHours) * hourlyRate
    }
}
