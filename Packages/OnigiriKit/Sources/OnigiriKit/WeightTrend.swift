import Foundation

/// Pure math over weigh-in history: smoothing and trend projection.
/// Raw scale readings swing a pound or two day to day; the moving average
/// is what goal progress and projections should use.
public enum WeightTrend {
    public struct Point: Sendable, Equatable {
        public let date: Date
        public let weightLb: Double

        public init(date: Date, weightLb: Double) {
            self.date = date
            self.weightLb = weightLb
        }
    }

    /// Trailing moving average: each point becomes the mean of all readings
    /// in the `windowDays` ending at its date. Input must be date-ascending.
    /// Sliding window over prefix sums — the filter-per-point version was
    /// O(n²) and ran from chart render paths over a year of weigh-ins.
    public static func movingAverage(_ points: [Point], windowDays: Int = 7) -> [Point] {
        guard !points.isEmpty else { return [] }
        let window = TimeInterval(windowDays) * 86400
        var prefix: [Double] = [0]
        prefix.reserveCapacity(points.count + 1)
        for point in points {
            prefix.append(prefix[prefix.count - 1] + point.weightLb)
        }
        var result: [Point] = []
        result.reserveCapacity(points.count)
        var low = 0   // first index still inside the window
        var high = 0  // exclusive upper bound of dates <= the current date
        for (index, point) in points.enumerated() {
            while low < points.count,
                  point.date.timeIntervalSince(points[low].date) >= window {
                low += 1
            }
            if high < index + 1 { high = index + 1 }
            // Same-timestamp readings later in the array count too,
            // matching the filter this replaces.
            while high < points.count, points[high].date <= point.date {
                high += 1
            }
            let mean = (prefix[high] - prefix[low]) / Double(high - low)
            result.append(Point(date: point.date, weightLb: mean))
        }
        return result
    }

    /// Predicted vs actual weight change over a window — the "did the math
    /// show up on the scale" comparison on Calendar and Goal.
    public enum Change {
        static let kcalPerLb = 3_500.0

        /// Lb change implied by a net calorie deficit (negative = lost).
        public static func predictedLb(totalDeficitKcal: Double) -> Double {
            -totalDeficitKcal / kcalPerLb
        }

        /// Scale change (lb) across the window, read from the 7-day moving
        /// average so single noisy weigh-ins don't swing it: last smoothed
        /// point in the window minus the first. Nil until the window holds
        /// two smoothed points on different days.
        public static func actualLb(
            history: [Point],
            from start: Date,
            to end: Date
        ) -> Double? {
            actualLb(smoothed: movingAverage(history, windowDays: 7), from: start, to: end)
        }

        /// The same read over ALREADY-smoothed points — for callers that
        /// hold the 7-day moving average (GoalTrendStats receives it from
        /// GoalModel); re-smoothing the raw history here was a redundant
        /// O(n) pass on every goal-form keystroke.
        public static func actualLb(
            smoothed: [Point],
            from start: Date,
            to end: Date
        ) -> Double? {
            let windowed = smoothed.filter { $0.date >= start && $0.date <= end }
            guard let first = windowed.first, let last = windowed.last,
                  first.date < last.date else { return nil }
            return last.weightLb - first.weightLb
        }
    }

    /// Least-squares slope in lb/day. Negative means losing weight.
    /// Nil when there are fewer than two distinct dates.
    public static func slopeLbPerDay(_ points: [Point]) -> Double? {
        guard points.count >= 2 else { return nil }
        let days = points.map { $0.date.timeIntervalSince(points[0].date) / 86400 }
        let weights = points.map(\.weightLb)
        let n = Double(points.count)
        let sumX = days.reduce(0, +)
        let sumY = weights.reduce(0, +)
        let sumXY = zip(days, weights).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = days.reduce(0) { $0 + $1 * $1 }
        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return nil }
        return (n * sumXY - sumX * sumY) / denominator
    }
}
