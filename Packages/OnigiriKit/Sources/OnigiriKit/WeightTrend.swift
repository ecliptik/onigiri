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

        /// Scale change (lb) across the window: an unweighted linear fit
        /// over the RAW weigh-ins inside it, read between the first and
        /// last reading's dates. The fit absorbs single noisy weigh-ins
        /// the way the old smoothed-endpoint read did, without its lag —
        /// the trailing average's endpoints under-reported a young
        /// history's movement by roughly half (the same ramp-in artifact
        /// the goal projection had). It never extrapolates past the data,
        /// so a month-in-progress reads month-to-date, not a guess.
        /// Nil until the window holds readings at least a day apart.
        public static func actualLb(
            history: [Point],
            from start: Date,
            to end: Date
        ) -> Double? {
            let windowed = history.filter { $0.date >= start && $0.date <= end }
            guard let first = windowed.first, let last = windowed.last else { return nil }
            let spanDays = last.date.timeIntervalSince(first.date) / 86400
            guard spanDays >= 1,
                  let fit = WeightTrend.fit(windowed, reference: last.date, lambda: 0)
            else { return nil }
            return fit.slopeLbPerDay * spanDays
        }
    }

    /// A fitted trend line, evaluated where the projection needs it.
    public struct LinearFit: Equatable, Sendable {
        /// lb/day; negative means losing weight.
        public let slopeLbPerDay: Double
        /// The line's value at the reference date — the de-noised
        /// current weight. (A trailing moving average lags a real loss
        /// by days; the fit's endpoint doesn't.)
        public let currentLb: Double

        public init(slopeLbPerDay: Double, currentLb: Double) {
            self.slopeLbPerDay = slopeLbPerDay
            self.currentLb = currentLb
        }
    }

    /// Recency-weighted least squares over RAW weigh-ins: each reading's
    /// influence halves per `halfLifeDays` of age, so the fit answers
    /// "what's the trend now", not "what was the window's average trend"
    /// — a diet started last week outweighs the flat weeks before it.
    /// Raw points on purpose: least squares already absorbs the
    /// morning/evening wobble, while fitting the trailing moving average
    /// (the old projection input) halved a fresh trend's slope for its
    /// first week — the average was still ramping in — and quoted goal
    /// dates weeks late. The under-read that remains in week one is a
    /// feature, not a bug: early loss is partly water, so converging
    /// over a couple of weeks beats extrapolating day three.
    /// Nil with fewer than two distinct timestamps.
    public static func recencyWeightedFit(
        _ points: [Point],
        reference: Date,
        halfLifeDays: Double = 7
    ) -> LinearFit? {
        fit(points, reference: reference, lambda: log(2.0) / (halfLifeDays * 86400))
    }

    /// The weighted-least-squares core: lambda 0 is a plain (unweighted)
    /// fit — what window-change reads want ("what happened over the
    /// window"), where the projection wants recency ("what's the trend
    /// now").
    static func fit(_ points: [Point], reference: Date, lambda: Double) -> LinearFit? {
        var sumW = 0.0, sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0
        for point in points {
            let age = point.date.timeIntervalSince(reference) // ≤ 0 in the past
            let x = age / 86400
            let w = exp(lambda * age)
            sumW += w
            sumX += w * x
            sumY += w * point.weightLb
            sumXX += w * x * x
            sumXY += w * x * point.weightLb
        }
        // Weighted variance of the dates; ~0 means one distinct timestamp.
        let denominator = sumW * sumXX - sumX * sumX
        guard denominator > 1e-9 else { return nil }
        let slope = (sumW * sumXY - sumX * sumY) / denominator
        return LinearFit(
            slopeLbPerDay: slope,
            currentLb: (sumY - slope * sumX) / sumW
        )
    }
}
