import Foundation

/// Could the selected AI provider not answer RIGHT NOW — or did it
/// answer with something the user needs to see?
///
/// The distinction exists because a provider that is unreachable is not
/// a provider that said no. Identifying food in an area with no cell
/// coverage failed all the way down to the deterministic path while a
/// perfectly good on-device model sat idle (the user, 2026-08-07), and
/// nothing downstream could tell that apart from a refusal because
/// every remote failure collapsed to `nil`.
///
/// Pure and total: no I/O, no state. This is the ONLY place the two
/// lists live.
public enum AIReachability {
    /// True = couldn't get an answer now, so another engine may try.
    /// False = the provider answered, and the answer is a problem the
    /// user should see rather than have papered over.
    public static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return transientURLCodes.contains(urlError.code)
        }
        if case AIChatError.badStatus(let code, _) = error {
            return transientStatusCodes(code)
        }
        // Anything else — a decode failure, an empty completion, a bad
        // response shape — means bytes came back. The provider is
        // reachable and the trouble is elsewhere.
        return false
    }

    /// The request could not be made, or could not complete.
    ///
    /// `.secureConnectionFailed` is deliberately here: captive portals
    /// (hotel, café, airport) fail exactly this way and are "no
    /// internet" in every sense the user cares about. Certificate-TRUST
    /// failures are deliberately NOT here — that is a misconfiguration
    /// on a local server, and silently routing around it would hide it
    /// forever.
    static let transientURLCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .timedOut,
        .dataNotAllowed,
        .internationalRoamingOff,
        .callIsActive,
        .secureConnectionFailed,
    ]

    /// The provider answered, but with "not now": request timeout, rate
    /// limit, or a server-side fault. Every other 4xx is the caller's
    /// problem to see — 401/403 above all, because a key that silently
    /// stops working must not look identical to one that works.
    static func transientStatusCodes(_ code: Int) -> Bool {
        code == 408 || code == 429 || (500...599).contains(code)
    }
}
