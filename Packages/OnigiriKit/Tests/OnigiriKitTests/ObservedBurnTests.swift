import Testing
import Foundation
@testable import OnigiriKit

/// The figure that makes the "Last 30 days" gap legible — what the SCALE
/// says you burn, against what the watch measured.
struct ObservedBurnTests {
    /// The worked example from the type's own doc, and the sign that
    /// matters: losing weight means burning MORE than was eaten, so a
    /// negative rate has to push the answer UP.
    @Test func losingWeightImpliesBurningMoreThanWasEaten() {
        // 2 lb over 30 days = -0.0667 lb/day.
        let observed = ObservedBurn.kcalPerDay(
            meanDailyIntakeKcal: 2_000,
            scaleRateLbPerDay: -2.0 / 30.0,
            trackedDays: 30
        )
        #expect(observed != nil)
        #expect(abs((observed ?? 0) - 2_233.3) < 1)
    }

    /// The opposite sign, because getting it backwards is the whole risk
    /// and it would still produce a plausible-looking number.
    @Test func gainingWeightImpliesBurningLessThanWasEaten() {
        let observed = ObservedBurn.kcalPerDay(
            meanDailyIntakeKcal: 2_000,
            scaleRateLbPerDay: 2.0 / 30.0,
            trackedDays: 30
        )
        #expect(abs((observed ?? 0) - 1_766.7) < 1)
    }

    /// A flat scale means you ate what you burned, whatever the watch
    /// says — the one case where the answer is exactly the intake.
    @Test func aFlatScaleMeansYouAteWhatYouBurned() {
        #expect(ObservedBurn.kcalPerDay(
            meanDailyIntakeKcal: 2_400, scaleRateLbPerDay: 0, trackedDays: 30
        ) == 2_400)
    }

    /// Silence, not a zero and not a guess. The mean intake of the
    /// tracked days stands in for every day the scale moved across, and
    /// that substitution stops being honest when most of the window went
    /// unlogged.
    @Test func aThinWindowSaysNothingAtAll() {
        #expect(ObservedBurn.kcalPerDay(
            meanDailyIntakeKcal: 2_000,
            scaleRateLbPerDay: -2.0 / 30.0,
            trackedDays: ObservedBurn.minimumTrackedDays - 1
        ) == nil)
        // And speaks the moment the window is thick enough.
        #expect(ObservedBurn.kcalPerDay(
            meanDailyIntakeKcal: 2_000,
            scaleRateLbPerDay: -2.0 / 30.0,
            trackedDays: ObservedBurn.minimumTrackedDays
        ) != nil)
    }

    /// A RATE, not a window total — so how OFTEN someone weighs in
    /// cannot change the answer. Two identical months, one weighed
    /// daily and one weighed twice, must read the same.
    @Test func theAnswerDoesNotDependOnHowOftenYouWeighIn() {
        let rate = -1.4 / 30.0
        let daily = ObservedBurn.kcalPerDay(
            meanDailyIntakeKcal: 1_900, scaleRateLbPerDay: rate, trackedDays: 30)
        let sparse = ObservedBurn.kcalPerDay(
            meanDailyIntakeKcal: 1_900, scaleRateLbPerDay: rate, trackedDays: 22)
        #expect(daily == sparse)
    }

    /// The rate and the window total come off ONE fit, so they can never
    /// disagree about which readings or which span.
    @Test func theRateAndTheTotalAgreeAboutTheSameWindow() {
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let start = now.addingTimeInterval(-30 * 86_400)
        // A clean 3 lb fall across the window.
        let history = (0...30).map { day in
            WeightTrend.Point(
                date: start.addingTimeInterval(Double(day) * 86_400),
                weightLb: 210 - 0.1 * Double(day))
        }
        let total = WeightTrend.Change.actualLb(history: history, from: start, to: now)
        let rate = WeightTrend.Change.actualRateLbPerDay(history: history, from: start, to: now)
        #expect(total != nil && rate != nil)
        // 30 days of span at the fitted rate reproduces the total.
        #expect(abs((rate ?? 0) * 30 - (total ?? 0)) < 0.01)
        #expect(abs((rate ?? 0) - -0.1) < 0.001)
    }
}
