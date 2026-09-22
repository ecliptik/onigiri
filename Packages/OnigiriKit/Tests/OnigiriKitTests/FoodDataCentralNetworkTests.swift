import Foundation
import Testing
@testable import OnigiriKit

/// FDC's own URLProtocol stub — a separate class from
/// OpenFoodFactsNetworkTests' on purpose: `.serialized` only orders
/// tests WITHIN a suite, so two suites sharing one stub's static
/// handler would race each other.
final class FDCStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.requestCount += 1
        Self.lastRequest = request
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The HTTP error mapping, the fail-fast/retry split, and the POST
/// requirement — the audit (2026-08-17) found only the pure JSON
/// parsing tested here while the sibling OpenFoodFacts client had all
/// of this covered. Mirrors that suite's stub pattern.
@Suite(.serialized)
struct FoodDataCentralNetworkTests {
    private func client(status: Int, body: String = "{}") -> FoodDataCentralClient {
        FDCStubURLProtocol.handler = { _ in (status, Data(body.utf8)) }
        FDCStubURLProtocol.requestCount = 0
        FDCStubURLProtocol.lastRequest = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FDCStubURLProtocol.self]
        return FoodDataCentralClient(
            apiKey: "TESTKEY", session: URLSession(configuration: configuration))
    }

    /// 403 is the user-actionable case — the fix is in Settings, and a
    /// retry can never help, so it must fail on the FIRST request.
    @Test func rejectedKeyFailsFastAsBadAPIKey() async {
        let client = client(status: 403)
        await #expect(throws: FoodDataCentralError.badAPIKey) {
            _ = try await client.search(query: "grapes")
        }
        #expect(FDCStubURLProtocol.requestCount == 1)
    }

    @Test func throttledFailsFastWithoutRetries() async {
        // A spent hourly quota can't clear inside the backoff window.
        let client = client(status: 429)
        await #expect(throws: FoodDataCentralError.throttled) {
            _ = try await client.search(query: "grapes")
        }
        #expect(FDCStubURLProtocol.requestCount == 1)
    }

    @Test(.timeLimit(.minutes(1))) func serverBusyRetriesThreePassesThenSurfacesBusy() async {
        // 5xx is momentary shedding: three passes (0s/1s/2s backoff),
        // then the actionable "busy" error — the OFF search contract.
        let client = client(status: 503)
        await #expect(throws: FoodDataCentralError.serverBusy) {
            _ = try await client.search(query: "grapes")
        }
        #expect(FDCStubURLProtocol.requestCount == 3)
    }

    /// The documented landmine (CLAUDE.md): the gateway 400s any GET
    /// whose query string carries the "Survey (FNDDS)" parens, so
    /// search MUST go out as POST, key in the URL. A regression here
    /// used to be visible only as a live production failure.
    @Test func searchGoesOutAsPostWithTheKeyInTheURL() async {
        let client = client(status: 403) // fail fast — one request to inspect
        _ = try? await client.search(query: "grapes")
        let request = FDCStubURLProtocol.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.query()?.contains("api_key=TESTKEY") == true)
    }

    @Test func portionsMapsTheRejectedKeyToo() async {
        let client = client(status: 403)
        await #expect(throws: FoodDataCentralError.badAPIKey) {
            _ = try await client.portions(fdcId: 12345)
        }
        #expect(FDCStubURLProtocol.requestCount == 1)
    }
}
