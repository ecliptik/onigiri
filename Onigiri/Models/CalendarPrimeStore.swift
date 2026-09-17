import Foundation
import OnigiriKit

/// The disk half of `CalendarPrime` (OnigiriKit), via `PrimeFile`.
enum CalendarPrimeStore {
    private static let file = "calendar-prime.json"

    /// Read ONCE per process, on first use (`GoalPrimeStore`).
    static let launchPrime: CalendarPrime? = {
        guard let prime = PrimeFile.read(file, as: CalendarPrime.self), prime.isValid()
        else { return nil }
        return prime
    }()

    static func store(_ prime: CalendarPrime) {
        guard prime.isTrustworthy else { return }
        PrimeFile.write(prime, to: file)
    }
}
