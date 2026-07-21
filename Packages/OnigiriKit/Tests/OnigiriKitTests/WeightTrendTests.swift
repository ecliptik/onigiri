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

    @Test func fitDetectsSteadyLoss() throws {
        // Losing exactly 0.1 lb/day; exact linear data fits exactly
        // regardless of the recency weights.
        let points = (0..<21).map { point(day: $0, 200 - 0.1 * Double($0)) }
        let fit = try #require(
            WeightTrend.recencyWeightedFit(points, reference: points.last!.date)
        )
        #expect(abs(fit.slopeLbPerDay - (-0.1)) < 0.001)
        #expect(abs(fit.currentLb - 198.0) < 0.01)
    }

    @Test func fitNilWithoutTwoDistinctTimestamps() {
        let reference = point(day: 1, 0).date
        #expect(WeightTrend.recencyWeightedFit([], reference: reference) == nil)
        #expect(WeightTrend.recencyWeightedFit([point(day: 0, 200)], reference: reference) == nil)
        #expect(WeightTrend.recencyWeightedFit(
            [point(day: 0, 200), point(day: 0, 201)], reference: reference
        ) == nil)
    }

    @Test func flatTrendFitsZeroSlope() throws {
        let points = (0..<10).map { point(day: $0, 195) }
        let fit = try #require(
            WeightTrend.recencyWeightedFit(points, reference: points.last!.date)
        )
        #expect(abs(fit.slopeLbPerDay) < 0.0001)
        #expect(abs(fit.currentLb - 195) < 0.001)
    }

    @Test func recentTrendOutweighsOldPlateau() throws {
        // Two flat weeks, then 0.3 lb/day down for a week. An unweighted
        // fit averages the plateau in (-0.087 lb/day); the recency
        // weights read most of the current rate.
        let points = (0..<14).map { point(day: $0, 200) }
            + (14..<21).map { point(day: $0, 200 - 0.3 * Double($0 - 13)) }
        let fit = try #require(
            WeightTrend.recencyWeightedFit(points, reference: points.last!.date)
        )
        #expect(fit.slopeLbPerDay < -0.11)
        #expect(fit.slopeLbPerDay > -0.30)
        // De-noised current tracks the recent drop (raw last is 197.9),
        // not the window average (~199.3).
        #expect(fit.currentLb < 198.6)
    }

    @Test func fitExtrapolatesToTheReferenceDate() throws {
        // Last weigh-in two days before the reference: the fitted
        // current carries the line forward, not the stale last reading.
        let points = (0...10).map { point(day: $0, 200 - 0.2 * Double($0)) }
        let fit = try #require(
            WeightTrend.recencyWeightedFit(points, reference: point(day: 12, 0).date)
        )
        #expect(abs(fit.currentLb - 197.6) < 0.01)
        #expect(abs(fit.slopeLbPerDay - (-0.2)) < 0.001)
    }
}
