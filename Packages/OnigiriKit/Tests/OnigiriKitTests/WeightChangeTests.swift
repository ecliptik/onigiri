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

    @Test func actualReadsSmoothedEndpointsInsideTheWindow() {
        // A steady 0.2 lb/day drop: the 7-day average lags the raw values,
        // but endpoints a window apart still show the loss direction.
        let history = (0...30).map { point(day: $0, lb: 200 - Double($0) * 0.2) }
        let change = WeightTrend.Change.actualLb(
            history: history,
            from: day0,
            to: day0.addingTimeInterval(30 * 86_400)
        )
        // 0.2 lb/day for 30 days ≈ 6 lb lost; the trailing average lags a
        // few tenths behind the raw drop, so accept a band.
        #expect(change != nil)
        if let change {
            #expect(change < -5 && change > -6.5)
        }
    }

    @Test func actualNilWithoutTwoPointsInWindow() {
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
    }

    @Test func noiseBarelyMovesTheSmoothedChange() {
        // ±0.6 lb sawtooth around a flat 200: raw endpoints could differ
        // by 1.2 lb, but with both window endpoints fully smoothed (7 days
        // of trailing history each) the change stays near zero.
        let history = (0...20).map { point(day: $0, lb: 200 + ($0 % 2 == 0 ? 0.6 : -0.6)) }
        let change = WeightTrend.Change.actualLb(
            history: history,
            from: day0.addingTimeInterval(8 * 86_400),
            to: day0.addingTimeInterval(20 * 86_400)
        )
        #expect(abs(change ?? 10) < 0.3)
    }
}
