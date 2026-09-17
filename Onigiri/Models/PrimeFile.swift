import Foundation

/// One JSON file in Caches per screen's first-frame prime — a cache by
/// name and by nature, so the system may evict it and the app must never
/// miss it. `GoalPrimeStore` and `CalendarPrimeStore` are this plus a
/// file name and the kit type's own validity rules.
enum PrimeFile {
    private static func url(_ name: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name)
    }

    /// Synchronous: a few KB, read before a first frame.
    static func read<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Off the main actor, atomically.
    static func write<T: Encodable & Sendable>(_ value: T, to name: String) {
        guard let url = url(name) else { return }
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
