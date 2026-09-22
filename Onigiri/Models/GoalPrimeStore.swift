import Foundation
import OnigiriKit

/// The disk half of `GoalPrime` (OnigiriKit), via `PrimeFile`.
enum GoalPrimeStore {
    private static let file = "goal-prime.json"

    /// Read ONCE per process, on first use — only the first model of a
    /// launch can use a prime, and it asks from `.onAppear`.
    static let launchPrime: GoalPrime? = {
        guard let prime = PrimeFile.read(file, as: GoalPrime.self), prime.isValid()
        else { return nil }
        return prime
    }()

    static func store(_ prime: GoalPrime) {
        guard prime.isTrustworthy else { return }
        PrimeFile.write(prime, to: file)
    }
}
