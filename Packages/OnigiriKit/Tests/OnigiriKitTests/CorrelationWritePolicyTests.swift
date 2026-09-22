import Testing
@testable import OnigiriKit

/// Pins the 2.1.3 fix: HealthKit rejects a whole food correlation when
/// one sample's type isn't write-authorized, so rows are filtered on
/// positive value AND write authorization.
struct CorrelationWritePolicyTests {
    @Test func authorizedPositiveValueWrites() {
        #expect(CorrelationWritePolicy.includes(value: 320, isWriteAuthorized: true))
    }

    @Test func unauthorizedTypeIsSkipped() {
        // The scanned-food case: a rich nutrient the user never granted
        // must be dropped, not fail the whole log.
        #expect(!CorrelationWritePolicy.includes(value: 320, isWriteAuthorized: false))
    }

    @Test func missingAndNonPositiveValuesAreSkipped() {
        #expect(!CorrelationWritePolicy.includes(value: nil, isWriteAuthorized: true))
        #expect(!CorrelationWritePolicy.includes(value: 0, isWriteAuthorized: true))
        #expect(!CorrelationWritePolicy.includes(value: -5, isWriteAuthorized: true))
    }

    @Test func authorizationIsOnlyProbedWhenAValueExists() {
        // The probe can touch the health store — value-less rows must
        // short-circuit before it runs.
        var probed = false
        func probe() -> Bool {
            probed = true
            return true
        }
        _ = CorrelationWritePolicy.includes(value: nil, isWriteAuthorized: probe())
        #expect(!probed)
        _ = CorrelationWritePolicy.includes(value: 12, isWriteAuthorized: probe())
        #expect(probed)
    }
}
