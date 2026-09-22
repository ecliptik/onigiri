import Foundation

/// Whether a weight goal has actually been REACHED, as opposed to
/// touched by one lucky morning.
///
/// The old rule was `latest weigh-in <= target`, which fired off a raw
/// reading the budget itself deliberately ignores — the plan is derived
/// from the smoothed basis, so Goal could celebrate while the numbers
/// beside it still planned a deficit. This is the sustained answer, and
/// it is the same shape as the basis wherever it can be.
///
/// Two rules, and the second exists because the first alone locks people
/// out:
/// - **preferred**: at least `minimumWeighInDays` weigh-in days inside
///   the trailing `preferredWindowDays` — the window the budget plans
///   from — and their mean at/below target.
/// - **widened**: when the preferred window can't find that many, fall
///   back to the most recent `minimumWeighInDays` weigh-in days, so long
///   as the oldest is within `maximumWindowDays`. Someone who weighs
///   weekly can never put three days inside seven, and without this the
///   celebration would be unreachable for them no matter how far below
///   target they got.
///
/// The widened basis is NOT the number the budget plans from — it
/// deliberately reaches further back. `usedWiderWindow` says which rule
/// answered, so no surface presents one as the other.
public struct GoalCompletion: Equatable, Sendable {
    /// The window the budget itself plans from — preferred, not required.
    public static let preferredWindowDays = 7
    /// How far back the search may reach for a third weigh-in day.
    /// Beyond this there is nothing recent enough to call current.
    public static let maximumWindowDays = 30
    /// One reading is a morning, not a result.
    public static let minimumWeighInDays = 3

    public let targetLb: Double
    /// Mean of the daily lows the rule selected; nil when it couldn't
    /// find enough of them.
    public let basisLb: Double?
    /// How many weigh-in DAYS backed that mean (never samples: two
    /// readings on one morning are one day).
    public let weighInDays: Int
    /// False when the preferred window sufficed.
    public let usedWiderWindow: Bool

    public var isMet: Bool {
        weighInDays >= Self.minimumWeighInDays
            && (basisLb.map { $0 <= targetLb } ?? false)
    }

    public static func evaluate(
        targetLb: Double,
        history: [WeightTrend.Point],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoalCompletion {
        // Daily lows, so an evening weigh-in (2–3 lb high) can't decide
        // a day and two readings before breakfast can't buy two days.
        let preferred = WeightTrend.recentDailyLows(
            history, windowDays: preferredWindowDays, now: now, calendar: calendar)
        if preferred.count >= minimumWeighInDays {
            return GoalCompletion(
                targetLb: targetLb, basisLb: mean(preferred),
                weighInDays: preferred.count, usedWiderWindow: false)
        }
        // Widen: the SMALLEST window holding enough days, which is the
        // most recent N — not everything inside the cap. "Average the
        // last month" is a different number, and it would let a reading
        // four weeks old drag a current result around.
        let reachable = WeightTrend.recentDailyLows(
            history, windowDays: maximumWindowDays, now: now, calendar: calendar)
        guard reachable.count >= minimumWeighInDays else {
            return GoalCompletion(
                targetLb: targetLb, basisLb: nil,
                weighInDays: reachable.count, usedWiderWindow: true)
        }
        let newest = Array(reachable.suffix(minimumWeighInDays))
        return GoalCompletion(
            targetLb: targetLb, basisLb: mean(newest),
            weighInDays: newest.count, usedWiderWindow: true)
    }

    private static func mean(_ points: [WeightTrend.Point]) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.reduce(0) { $0 + $1.weightLb } / Double(points.count)
    }

    /// How far above a maintenance anchor counts as having drifted back
    /// up. Daily weight swings 2–3 lb, but this is measured on the
    /// SMOOTHED basis, so five pounds above the anchor is a real move
    /// rather than a heavy dinner — and it is the step people count in.
    public static let regainToleranceLb = 5.0

    /// Whether the scale has settled meaningfully ABOVE a maintenance
    /// anchor — the mirror of `isMet`, on the same sustained basis and
    /// the same weigh-in guard, so it cannot fire off one bad morning.
    ///
    /// Deliberately a plain Bool with no "by how much" in it: what a
    /// surface does with this has to be an offer, not a verdict.
    public static func hasRegained(
        anchorLb: Double,
        history: [WeightTrend.Point],
        toleranceLb: Double = regainToleranceLb,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let reading = evaluate(
            targetLb: anchorLb, history: history, now: now, calendar: calendar)
        guard reading.weighInDays >= minimumWeighInDays,
              let basis = reading.basisLb
        else { return false }
        return basis >= anchorLb + toleranceLb
    }
}

/// Whether a milestone is NEW — deeper than the deepest one already
/// seen.
///
/// Quieter than `GoalReachedCard` by design: a 40 lb journey posts seven
/// rungs, and a card apiece would make the target stop feeling like an
/// arrival. So a rung is a LINE in the Daily goal card, shown on the day
/// it is crossed and no other (the user, 2026-08-11) — which is why
/// there is no dismissal here to model. The caller pairs this with the
/// stamp's date; this half only answers "is this one new".
///
/// One number carries it: recording "15 lb down" settles everything at
/// or below 15, and a later 20 lb rung still reads as new.
public enum MilestoneCard {
    public static func isNew(lostLb: Double?, seenLostLb: Double) -> Bool {
        guard let lostLb, lostLb > 0 else { return false }
        // A hair of slack, since these are floating-point multiples of a
        // step (3 × 4.4 lb for a 2 kg step won't land exactly).
        return lostLb > seenLostLb + 0.001
    }
}

/// When the "you hit your target" card should appear on Today.
///
/// A small state machine on purpose: the rule is "announce it, let it be
/// dismissed, say it once more two weeks later if nothing was decided,
/// then never again for that target" — and "shows twice, never three
/// times" is exactly the kind of rule that rots silently inside a view.
///
/// The re-arm is not a nag for its own sake. Sitting at target without
/// deciding grades days MORE permissively than either real mode (a
/// zero-deficit day stamps "any deficit earns the badge", where
/// maintenance uses the band rule), and that drift is otherwise
/// invisible forever.
public enum GoalReachedCard {
    /// How long after a dismissal the card returns, if still at target
    /// and still undecided.
    public static let reArmDays = 14
    /// Dismissals after which the card is done for this target. A
    /// DECISION jumps straight here — it is not a dismissal, and it must
    /// not leave a re-arm loaded.
    public static let maximumShows = 2

    /// `ackTarget` is the target the stored acknowledgement belongs to,
    /// so a NEW target re-arms the card for free and bouncing above and
    /// back below the same one never re-celebrates.
    public static func shouldShow(
        isMet: Bool,
        isMaintenance: Bool,
        targetLb: Double?,
        ackTarget: Double,
        ackCount: Int,
        ackAt: Date?,
        now: Date = .now
    ) -> Bool {
        guard isMet, !isMaintenance, let targetLb else { return false }
        // A stored acknowledgement for some OTHER target says nothing
        // about this one.
        guard ackTarget == targetLb else { return true }
        guard ackCount < maximumShows else { return false }
        guard let ackAt else { return true }
        return now >= ackAt.addingTimeInterval(Double(reArmDays) * 86400)
    }
}
