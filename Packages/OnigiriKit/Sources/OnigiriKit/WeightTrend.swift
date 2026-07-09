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
    public static func movingAverage(_ points: [Point], windowDays: Int = 7) -> [Point] {
        guard !points.isEmpty else { return [] }
        let window = TimeInterval(windowDays) * 86400
        return points.map { point in
            let inWindow = points.filter {
                $0.date <= point.date && point.date.timeIntervalSince($0.date) < window
            }
            let mean = inWindow.reduce(0) { $0 + $1.weightLb } / Double(inWindow.count)
            return Point(date: point.date, weightLb: mean)
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
