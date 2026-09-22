import Foundation

/// A person-accepted, flat kcal/day offset on every day's burn — the
/// budget made to answer to the scale (`plans/PLAN-burn-correction.md`).
///
/// Health's measured burn ran a few hundred kcal/day above what the
/// weigh-ins implied — a gap the same size as the deficit the budget
/// builds in, so eating to budget landed near maintenance. `ObservedBurn` REPORTED that gap from
/// 2026-08-18; this is the stored, reversible answer to it.
///
/// **It never recomputes itself.** The stored value (`SharedStore
/// .burnCorrectionKcal`) changes only when a person taps something. The
/// SUGGESTION below is derived live, but it is an offer on a screen, not
/// an input to any budget. A correction that refreshed itself would be
/// A3 — the continuous adaptive TDEE `PLAN-earned-budget` deleted — and
/// the distinguishing property is not where the number came from but
/// whether a human agreed to it.
///
/// **It re-grades history, and that is decided, not overlooked.** A
/// day's TARGET is frozen by its `DeficitTargetHistory` snapshot; a
/// day's MEASUREMENT never was, and a correction is a measurement. So it
/// flows through `DayBudget.dayBurn` into every day `dailyEnergyTotals`
/// returns — calendar, badges, streak, "Total deficit" alike.
///
/// It absorbs whatever caused the gap, under-logging included, which is
/// why the offer states what it was calibrated against and over how
/// many days: taking it before a fortnight of weighed logging has
/// separated the causes calibrates against a moving target.
public enum BurnCorrection {
    /// The furthest a correction may move any one burn, as a fraction of
    /// that burn. An uncapped correction fed a bad month produces a
    /// budget nobody should eat to.
    public static let capFraction = 0.2

    /// A suggestion smaller than this is not offered. The scale's own
    /// noise over a few weeks is tens of kcal/day; offering "−20" invites
    /// a re-grade of the whole calendar for nothing measurable.
    public static let minimumOfferKcal = 50.0

    /// Suggestions round to this, because the number is meant to be
    /// sanity-checked by a person and "−312.4" claims a precision the
    /// method does not have.
    public static let roundingKcal = 10.0

    /// `burnKcal` with the correction applied — the one composition
    /// point, reached from `DayBudget.dayBurn` and, for a day-ratcheted
    /// burn, directly (the ratchet guards the MEASUREMENT against
    /// Health revising down; the correction is applied after it, so
    /// accepting one mid-day takes effect at once instead of waiting
    /// out a high-water mark set before it existed).
    ///
    /// A correction of exactly 0 returns `burnKcal` untouched — no
    /// clamp, no floor, not even `+ 0`. That is what keeps every path
    /// byte-identical for everyone who never accepts an offer.
    ///
    /// Otherwise: clamped to ±`capFraction` of the burn, and a
    /// NEGATIVE correction may not take the burn below the body's
    /// resting estimate — the floor under resting is the floor's whole
    /// purpose, and "your burn was lower than your body at rest" is not
    /// a figure anyone should be budgeting from. With no estimate the
    /// floor is zero.
    public static func apply(
        toBurnKcal burnKcal: Double,
        estimatedRestingKcal: Double?,
        correctionKcal: Double
    ) -> Double {
        guard correctionKcal != 0, burnKcal > 0 else { return burnKcal }
        let cap = burnKcal * capFraction
        let clamped = min(cap, max(-cap, correctionKcal))
        let corrected = burnKcal + clamped
        guard clamped < 0 else { return corrected }
        // Never below the estimate — but never ABOVE the uncorrected
        // burn either, which a burn that was itself under the estimate
        // (it can't be via `dayBurn`, but a caller could pass one)
        // would otherwise produce: a negative correction that RAISED
        // the burn.
        let floor = min(burnKcal, max(0, estimatedRestingKcal ?? 0))
        return max(corrected, floor)
    }

    /// What the scale proposes, and what it was worked out from — the
    /// offer has to say both, since the sequencing decision rests on
    /// the person knowing how old and how deep the basis is.
    public struct Suggestion: Equatable, Sendable {
        /// Signed kcal/day, rounded to `roundingKcal`; negative lowers
        /// burn.
        public let kcalPerDay: Double
        /// Completed tracked days it was calibrated against.
        public let trackedDays: Int
        /// The earliest of them.
        public let since: Date
        /// What the weigh-ins imply was burned across those days, and
        /// what Health measured (uncorrected) — the two numbers whose
        /// difference this is.
        public let scaleBurnKcal: Double
        public let measuredBurnKcal: Double
    }

    /// The correction that would make the tracked days' measured burn
    /// agree with the scale — `ObservedBurn` over ALL completed tracked
    /// days on record, minus the mean uncorrected burn of those same
    /// days. Equivalently: the per-day offset that makes "Total
    /// deficit" land on the weight actually lost.
    ///
    /// All tracked days, not the trailing 30 (decided 2026-09-22): the
    /// shorter window suggested a larger correction, and the difference
    /// was mostly water sitting above the trend line — setting the
    /// correction from it would bake water into the budget as if it
    /// were metabolism.
    ///
    /// COMPLETED days only. Today's burn credits its resting up front
    /// and its intake is half-logged, so a partial day is exactly the
    /// kind of fiction `ObservedBurn`'s tracked-days rule keeps out.
    ///
    /// Reads `uncorrectedBurnKcal`, never `burnKcal`: once a correction
    /// is live the totals carry it, and a suggestion computed off
    /// corrected burn would answer "how much MORE" rather than "how
    /// much", and drift toward zero the moment it was accepted.
    ///
    /// nil — nothing offered — under `ObservedBurn.minimumTrackedDays`,
    /// without a weigh-in rate across the span, or when the answer is
    /// inside `minimumOfferKcal` of zero.
    public static func suggest(
        dailyTotals: [DayEnergyTotals],
        weightHistory: [WeightTrend.Point],
        untrackedBelowKcal: Double,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Suggestion? {
        let todayStart = calendar.startOfDay(for: now)
        let days = dailyTotals
            .filter { $0.day < todayStart }
            .filter { StreakCalendar.isTracked($0, untrackedBelowKcal: untrackedBelowKcal) }
            .sorted { $0.day < $1.day }
        guard let since = days.first?.day,
              let rate = WeightTrend.Change.actualRateLbPerDay(
                  history: weightHistory, from: since, to: now)
        else { return nil }
        let count = Double(days.count)
        let meanIntake = days.reduce(0) { $0 + $1.intakeKcal } / count
        let meanMeasured = days.reduce(0) { $0 + $1.uncorrectedBurnKcal } / count
        guard let scaleBurn = ObservedBurn.kcalPerDay(
            meanDailyIntakeKcal: meanIntake,
            scaleRateLbPerDay: rate,
            trackedDays: days.count
        ) else { return nil }
        let cap = meanMeasured * capFraction
        let raw = min(cap, max(-cap, scaleBurn - meanMeasured))
        let rounded = (raw / roundingKcal).rounded() * roundingKcal
        guard abs(rounded) >= minimumOfferKcal else { return nil }
        return Suggestion(
            kcalPerDay: rounded, trackedDays: days.count, since: since,
            scaleBurnKcal: scaleBurn, measuredBurnKcal: meanMeasured)
    }
}

public extension SharedStore {
    /// Signed kcal/day added to every day's burn; negative lowers it.
    /// Absent/0 is OFF — the default, and the disabled state; there is
    /// no separate switch to fall out of step with it.
    static let burnCorrectionKcalKey = "burnCorrectionKcal"
    /// When the stored correction was accepted, as seconds since 1970;
    /// absent/0 when there is none. Lets the screen say how old the
    /// basis is, which is half of what makes an early tap informed.
    static let burnCorrectionSetAtKey = "burnCorrectionSetAt"

    /// Both keys ALWAYS ride the watch settings sync with an explicit
    /// value (`WatchSync.planPreferencePairs`): a correction the phone
    /// has and the watch does not is the 2026-09-20 phone/watch budget
    /// disagreement, rebuilt on purpose.
    static var burnCorrectionKcal: Double {
        defaults.double(forKey: burnCorrectionKcalKey)
    }

    static var burnCorrectionSetAt: Date? {
        let stamp = defaults.double(forKey: burnCorrectionSetAtKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// The ONE writer, and the only way the stored correction changes:
    /// something a person tapped. 0 clears both keys' meaning (the stamp
    /// goes with it — "set on" a correction that is off would be a date
    /// about nothing).
    static func setBurnCorrection(kcal: Double, now: Date = .now) {
        defaults.set(kcal, forKey: burnCorrectionKcalKey)
        defaults.set(kcal == 0 ? 0 : now.timeIntervalSince1970, forKey: burnCorrectionSetAtKey)
    }
}
