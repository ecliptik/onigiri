import Foundation
import OnigiriKit

/// The disk half of `TodayPrime` (OnigiriKit): one JSON file in Caches —
/// a cache by name and by nature, so the system may evict it and the app
/// must never miss it. Read synchronously in `TodayModel.init` (a few KB,
/// before the first frame); written off the main actor after each
/// trustworthy refresh of today.
enum TodayPrimeStore {
    private static var url: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("today-prime.json")
    }

    static func load(now: Date = .now) -> TodayPrime? {
        guard let url, let data = try? Data(contentsOf: url),
              let prime = try? JSONDecoder().decode(TodayPrime.self, from: data),
              prime.isValid(now: now)
        else { return nil }
        return prime
    }

    static func store(_ prime: TodayPrime) {
        guard prime.isTrustworthy, let url else { return }
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(prime) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
