import Foundation
import Testing
@testable import OnigiriKit

/// A URLProtocol stub: every request the injected session makes lands
/// in `handler`, which returns (status, body). Serialized suite — the
/// handler is a shared static.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.requestCount += 1
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

/// The HTTP error mapping and retry structure — the audit found only
/// the pure JSON parsing tested, with every network branch (status
/// mapping, fail-fast vs retry) uncovered.
@Suite(.serialized)
struct OpenFoodFactsNetworkTests {
    private func client(status: Int, body: String = "{}") -> OpenFoodFactsClient {
        StubURLProtocol.handler = { _ in (status, Data(body.utf8)) }
        StubURLProtocol.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OpenFoodFactsClient(session: URLSession(configuration: configuration))
    }

    @Test func missingBarcodeMaps404ToNotFound() async {
        // Distinct barcodes per test: the process-wide ProductCache
        // stores successes, and a shared code would cross-pollinate.
        await #expect(throws: OpenFoodFactsError.notFound) {
            _ = try await client(status: 404).product(barcode: "404404")
        }
    }

    @Test func rateLimitMaps429ToThrottled() async {
        await #expect(throws: OpenFoodFactsError.throttled) {
            _ = try await client(status: 429).product(barcode: "429429")
        }
    }

    @Test func loadSheddingMaps503ToServerBusy() async {
        await #expect(throws: OpenFoodFactsError.serverBusy) {
            _ = try await client(status: 503).product(barcode: "503503")
        }
    }

    @Test func unexpectedStatusMapsToBadResponse() async {
        await #expect(throws: OpenFoodFactsError.badResponse) {
            _ = try await client(status: 500).product(barcode: "500500")
        }
    }

    @Test func malformedBodySurfacesTheDecodeError() async {
        let client = client(status: 200, body: "not json")
        await #expect(throws: DecodingError.self) {
            _ = try await client.product(barcode: "200200")
        }
    }

    @Test func productMissingFromA200MapsToNotFound() async {
        await #expect(throws: OpenFoodFactsError.notFound) {
            _ = try await client(status: 200, body: #"{"status": 0}"#).product(barcode: "200404")
        }
    }

    @Test func throttledSearchFailsFastWithoutRetries() async {
        // A 429 can't clear inside the backoff window — search must
        // stop after one pass (primary + legacy leg), not retry into
        // the rate-limit hole.
        let client = client(status: 429)
        await #expect(throws: OpenFoodFactsError.throttled) {
            _ = try await client.search(query: "grapes")
        }
        #expect(StubURLProtocol.requestCount == 2)
    }

    @Test(.timeLimit(.minutes(1))) func busySearchRetriesThreePassesThenSurfacesBusy() async {
        // 503s are momentary: three passes (0s/1s/2s backoff), two legs
        // each, then the actionable "busy" error — not a generic failure.
        let client = client(status: 503)
        await #expect(throws: OpenFoodFactsError.serverBusy) {
            _ = try await client.search(query: "grapes")
        }
        #expect(StubURLProtocol.requestCount == 6)
    }
}
