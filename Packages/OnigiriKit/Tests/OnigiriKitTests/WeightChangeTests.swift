import Foundation
import Testing
@testable import OnigiriKit

struct WeightChangeTests {
    private let day0 = Date(timeIntervalSince1970: 1_750_000_000)

    private func point(day: Int, lb: Double) -> WeightTrend.Point {
        WeightTrend.Point(date: day0.addingTimeInterval(Double(day) * 86_400), weightLb: lb)
    }

    @Test func predictedFollowsThirtyFiveHundredRule() {
        #expect(WeightTrend.Change.predictedLb(totalDeficitKcal: 3_500) == -1)
        #expect(WeightTrend.Change.predictedLb(totalDeficitKcal: 7_000) == -2)
        // A surplus month predicts gained weight.
        #expect(WeightTrend.Change.predictedLb(totalDeficitKcal: -1_750) == 0.5)
        #expect(WeightTrend.Change.predictedLb(totalDeficitKcal: 0) == 0)
    }

    @Test func actualReadsTheFittedChangeAcrossTheWindow() {
        // A steady 0.2 lb/day drop fits exactly: 30 days ⇒ −6.0 lb, no
        // smoothing lag eating into it (the old smoothed-endpoint read
        // came in shy).
        let history = (0...30).map { point(day: $0, lb: 200 - Double($0) * 0.2) }
        let change = WeightTrend.Change.actualLb(
            history: history,
            from: day0,
            to: day0.addingTimeInterval(30 * 86_400)
        )
        #expect(change != nil)
        if let change {
            #expect(abs(change - (-6.0)) < 0.001)
        }
    }

    @Test func youngHistoryReadsItsFullMovement() {
        // Weigh-ins only 8 days old inside a 30-day window: the change
        // is the data span's movement (−1.75 lb over 7 days at 0.25/day)
        // — the ramp-in artifact of the old smoothed read halved this,
        // and the fit must not extrapolate to the empty 3 weeks either.
        let history = (0...7).map { point(day: $0, lb: 200 - Double($0) * 0.25) }
        let change = WeightTrend.Change.actualLb(
            history: history,
            from: day0.addingTimeInterval(-23 * 86_400),
            to: day0.addingTimeInterval(7 * 86_400)
        )
        #expect(change != nil)
        if let change {
            #expect(abs(change - (-1.75)) < 0.01)
        }
    }

    @Test func actualNilWithoutASpanningWindow() {
        let history = [point(day: 0, lb: 200)]
        #expect(WeightTrend.Change.actualLb(
            history: history, from: day0, to: day0.addingTimeInterval(30 * 86_400)
        ) == nil)
        // Points exist but all outside the window.
        let outside = (0...5).map { point(day: $0, lb: 200) }
        #expect(WeightTrend.Change.actualLb(
            history: outside,
            from: day0.addingTimeInterval(40 * 86_400),
            to: day0.addingTimeInterval(70 * 86_400)
        ) == nil)
        // Two readings hours apart aren't a change — morning/evening
        // wobble would masquerade as one.
        let sameDay = [
            WeightTrend.Point(date: day0, weightLb: 199.2),
            WeightTrend.Point(date: day0.addingTimeInterval(13 * 3_600), weightLb: 200.6),
        ]
        #expect(WeightTrend.Change.actualLb(
            history: sameDay, from: day0, to: day0.addingTimeInterval(86_400)
        ) == nil)
    }

    @Test func noiseBarelyMovesTheFittedChange() {
        // ±0.6 lb sawtooth around a flat 200: raw endpoints could differ
        // by 1.2 lb, but the fit reads through the wobble to ~zero.
        let history = (0...20).map { point(day: $0, lb: 200 + ($0 % 2 == 0 ? 0.6 : -0.6)) }
        let change = WeightTrend.Change.actualLb(
            history: history,
            from: day0.addingTimeInterval(8 * 86_400),
            to: day0.addingTimeInterval(20 * 86_400)
        )
        #expect(abs(change ?? 10) < 0.3)
    }
}
