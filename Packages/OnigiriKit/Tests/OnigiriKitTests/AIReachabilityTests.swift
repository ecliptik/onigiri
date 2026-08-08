import Testing
import Foundation
@testable import OnigiriKit

struct AIReachabilityTests {
    private func urlError(_ code: URLError.Code) -> Error { URLError(code) }
    private func status(_ code: Int) -> Error { AIChatError.badStatus(code, nil) }

    // MARK: - Falls back: couldn't get an answer

    @Test func noNetworkIsTransient() {
        // The reported case: no cell coverage.
        #expect(AIReachability.isTransient(urlError(.notConnectedToInternet)))
        #expect(AIReachability.isTransient(urlError(.networkConnectionLost)))
        #expect(AIReachability.isTransient(urlError(.dataNotAllowed)))
        #expect(AIReachability.isTransient(urlError(.internationalRoamingOff)))
    }

    @Test func unreachableHostIsTransient() {
        // Also the local-provider case: off the LAN where Ollama lives.
        #expect(AIReachability.isTransient(urlError(.cannotConnectToHost)))
        #expect(AIReachability.isTransient(urlError(.cannotFindHost)))
        #expect(AIReachability.isTransient(urlError(.dnsLookupFailed)))
    }

    @Test func timeoutIsTransient() {
        #expect(AIReachability.isTransient(urlError(.timedOut)))
    }

    /// Captive portals fail this way and are "no internet" in every
    /// sense the user cares about. A fallback sends nothing, so erring
    /// toward it costs no privacy.
    @Test func captivePortalTLSFailureIsTransient() {
        #expect(AIReachability.isTransient(urlError(.secureConnectionFailed)))
    }

    @Test func rateLimitAndServerFaultsAreTransient() {
        #expect(AIReachability.isTransient(status(408)))
        #expect(AIReachability.isTransient(status(429)))
        #expect(AIReachability.isTransient(status(500)))
        #expect(AIReachability.isTransient(status(502)))
        #expect(AIReachability.isTransient(status(503)))
        #expect(AIReachability.isTransient(status(599)))
    }

    // MARK: - Does not fall back: the user needs to see this

    /// The one that matters most: a key that silently stops working
    /// must not look identical to a key that works.
    @Test func rejectedKeyIsNotTransient() {
        #expect(!AIReachability.isTransient(status(401)))
        #expect(!AIReachability.isTransient(status(403)))
    }

    @Test func clientErrorsAreNotTransient() {
        #expect(!AIReachability.isTransient(status(400)))
        #expect(!AIReachability.isTransient(status(404)))
        #expect(!AIReachability.isTransient(status(422)))
    }

    /// A certificate the device won't trust is a misconfiguration on a
    /// local server. Routing around it silently would hide it forever.
    @Test func certificateTrustFailuresAreNotTransient() {
        #expect(!AIReachability.isTransient(urlError(.serverCertificateUntrusted)))
        #expect(!AIReachability.isTransient(urlError(.serverCertificateHasBadDate)))
        #expect(!AIReachability.isTransient(urlError(.clientCertificateRejected)))
    }

    /// Bytes came back — the provider is reachable and the trouble is
    /// elsewhere (a refusal, a fence the extractor couldn't strip, a
    /// shape the decoder rejected).
    @Test func answeredButUnusableIsNotTransient() {
        #expect(!AIReachability.isTransient(AIChatError.emptyContent))
        #expect(!AIReachability.isTransient(AIChatError.badResponse))
        #expect(!AIReachability.isTransient(AIChatError.badURL))
    }

    @Test func unrelatedErrorsAreNotTransient() {
        struct Whatever: Error {}
        #expect(!AIReachability.isTransient(Whatever()))
        #expect(!AIReachability.isTransient(CocoaError(.fileNoSuchFile)))
        #expect(!AIReachability.isTransient(urlError(.unsupportedURL)))
        #expect(!AIReachability.isTransient(urlError(.cancelled)))
    }

    /// The status message rides along for Settings' connection test; it
    /// must not change the verdict either way.
    @Test func theServerMessageDoesNotChangeTheVerdict() {
        #expect(AIReachability.isTransient(AIChatError.badStatus(429, "slow down")))
        #expect(!AIReachability.isTransient(AIChatError.badStatus(401, "invalid x-api-key")))
    }
}
