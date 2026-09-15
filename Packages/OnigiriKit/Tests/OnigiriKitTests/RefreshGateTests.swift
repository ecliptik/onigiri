import Testing
import Foundation
@testable import OnigiriKit

/// Extracted out of four hand-rolled copies (health-check audit,
/// 2026-09-14) — see the type's own doc comment.
struct RefreshGateTests {
    private static let cal = Calendar(identifier: .gregorian)
    private static let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 12))!

    @Test func neverRefreshedIsStale() {
        let gate = RefreshGate()
        #expect(gate.isStale(maxAge: 30, now: Self.now, calendar: Self.cal))
    }

    @Test func freshWithinMaxAgeIsNotStale() {
        var gate = RefreshGate()
        gate.markRefreshed(at: Self.now.addingTimeInterval(-10))
        #expect(!gate.isStale(maxAge: 30, now: Self.now, calendar: Self.cal))
    }

    @Test func olderThanMaxAgeIsStale() {
        var gate = RefreshGate()
        gate.markRefreshed(at: Self.now.addingTimeInterval(-31))
        #expect(gate.isStale(maxAge: 30, now: Self.now, calendar: Self.cal))
    }

    @Test func aDayRolloverIsStaleEvenWithinMaxAge() {
        var gate = RefreshGate()
        // Same instant a day earlier — well within any reasonable
        // maxAge, but a different calendar day.
        gate.markRefreshed(at: Self.cal.date(byAdding: .day, value: -1, to: Self.now)!)
        #expect(gate.isStale(maxAge: 3600, now: Self.now, calendar: Self.cal))
    }

    @Test func resetForcesStaleRegardlessOfAge() {
        var gate = RefreshGate()
        gate.markRefreshed(at: Self.now)
        #expect(!gate.isStale(maxAge: 30, now: Self.now, calendar: Self.cal))
        gate.reset()
        #expect(gate.isStale(maxAge: 30, now: Self.now, calendar: Self.cal))
    }
}
