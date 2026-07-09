import Foundation
import Testing
@testable import OnigiriKit

struct WeightTrendTests {
    private func point(day: Int, _ weight: Double) -> WeightTrend.Point {
        WeightTrend.Point(
            date: Date(timeIntervalSinceReferenceDate: Double(day) * 86400),
            weightLb: weight
        )
    }

    @Test func movingAverageSmoothsNoise() {
        // Alternating ±1 around 200 should average out near 200.
        let points = (0..<14).map { point(day: $0, 200 + ($0.isMultiple(of: 2) ? 1.0 : -1.0)) }
        let smoothed = WeightTrend.movingAverage(points, windowDays: 7)
        #expect(smoothed.count == points.count)
        #expect(abs(smoothed.last!.weightLb - 200) < 0.6)
    }

    @Test func movingAverageFirstPointIsItself() {
        let points = [point(day: 0, 200), point(day: 1, 198)]
        let smoothed = WeightTrend.movingAverage(points)
        #expect(smoothed.first!.weightLb == 200)
        #expect(smoothed.last!.weightLb == 199)
    }

    @Test func slopeDetectsSteadyLoss() {
        // Losing exactly 0.1 lb/day.
        let points = (0..<21).map { point(day: $0, 200 - 0.1 * Double($0)) }
        let slope = WeightTrend.slopeLbPerDay(points)
        #expect(slope != nil)
        #expect(abs(slope! - (-0.1)) < 0.001)
    }

    @Test func slopeNilForSinglePoint() {
        #expect(WeightTrend.slopeLbPerDay([point(day: 0, 200)]) == nil)
    }

    @Test func flatTrendHasZeroSlope() {
        let points = (0..<10).map { point(day: $0, 195) }
        #expect(abs(WeightTrend.slopeLbPerDay(points)!) < 0.0001)
    }
}
