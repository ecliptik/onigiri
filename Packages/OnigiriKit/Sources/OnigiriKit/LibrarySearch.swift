import Foundation
import SwiftData

/// The buckets a library search sorts its matches into, in display
/// order.
///
/// A query searches the WHOLE library: the Favorites/Foods/Meals scope
/// bar is a BROWSING control, not a search filter. It read as one for
/// two releases because both surfaces applied the scope before the
/// query — searching "nectarine" while the Meals scope was up returned
/// nothing, with the nectarine sitting in the library the whole time
/// (the user, 2026-08-07).
public enum LibrarySearchGroup: String, CaseIterable, Sendable {
    // Declaration order IS display order, and it mirrors the scope
    // bar's own (Favorites leads).
    case favorites = "Favorites"
    case foods = "Foods"
    case meals = "Meals"
    /// Log sheet only: last week's logged entries with no library twin.
    /// Named rather than folded into Foods because those rows carry no
    /// ★ and no Edit — and since "Log" can now log without saving, they
    /// are the only way back to a one-off.
    case recentlyLogged = "Recently Logged"
}

/// What a row exposes to be searched and grouped.
///
/// The requirement names are deliberately distinct from the conforming
/// types' own spellings (`searchName`, not `name`). Conformers are
/// SwiftData models AND view structs whose properties differ in meaning
/// — an accidental protocol-witness match would be a silent
/// wrong-column bug rather than a compile error.
public protocol LibrarySearchable {
    var searchName: String { get }
    var searchCategory: String? { get }
    var isStarred: Bool { get }
    var isMealRow: Bool { get }
    var isHistoryRow: Bool { get }
    var searchRecency: Date { get }
}

/// The one implementation of cross-scope search, shared by the Foods
/// tab and the Log sheet. Both grew their own copy of the match rule
/// and the ranking; shared surfaces drift apart when each screen keeps
/// its own (the OnlineResultsSection lesson).
public enum LibrarySearch {
    /// Name OR category text, so "snack" still pulls up every snack.
    /// An empty query matches everything — callers gate on that
    /// themselves, but the rule shouldn't depend on it.
    ///
    /// `localizedStandardContains`, not the surfaces' old
    /// `localizedCaseInsensitiveContains`: standard adds DIACRITIC
    /// insensitivity, which is what the field already looked like it
    /// did — "creme brulee" found nothing while "Crème Brûlée" sat in
    /// the library. It can only ever add matches, never remove one.
    public static func matches(_ item: some LibrarySearchable, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        if item.searchName.localizedStandardContains(trimmed) { return true }
        return item.searchCategory?.localizedStandardContains(trimmed) ?? false
    }

    /// ONE home per row: a starred food lands in Favorites and NOT
    /// again under Foods, so the visible row count equals the match
    /// count. (Starred-and-history can't occur — history rows are built
    /// with no favorite flag — but favorites winning first states the
    /// precedence rather than leaving it to construction order.)
    public static func group(_ item: some LibrarySearchable) -> LibrarySearchGroup {
        if item.isStarred { return .favorites }
        if item.isHistoryRow { return .recentlyLogged }
        return item.isMealRow ? .meals : .foods
    }

    /// Query → the groups that have matches, in display order, empties
    /// dropped. `sortByRecency` false is the Name sort order.
    public static func groups<T: LibrarySearchable>(
        _ items: [T], query: String, sortByRecency: Bool = true
    ) -> [(group: LibrarySearchGroup, items: [T])] {
        let matched = items.filter { matches($0, query: query) }
        return LibrarySearchGroup.allCases.compactMap { group in
            let inGroup = matched
                .filter { Self.group($0) == group }
                .sorted { ranked($0, $1, byRecency: sortByRecency) }
            return inGroup.isEmpty ? nil : (group, inGroup)
        }
    }

    /// Recency first (what you actually eat), name for stability — the
    /// rule both surfaces already rank by.
    private static func ranked(
        _ lhs: some LibrarySearchable, _ rhs: some LibrarySearchable, byRecency: Bool
    ) -> Bool {
        if byRecency, lhs.searchRecency != rhs.searchRecency {
            return lhs.searchRecency > rhs.searchRecency
        }
        return lhs.searchName.localizedCaseInsensitiveCompare(rhs.searchName) == .orderedAscending
    }
}

extension LibrarySearch {
    /// The library list order: recency first unless the user asked for
    /// Name, and alphabetical as the tie-break either way.
    ///
    /// One rule, one implementation. Foods and the Log sheet each had
    /// their own spelling of it — `switch librarySort { case .recent }`
    /// in one, `if librarySort != .name` in the other — which is the
    /// same setup that let the menu-PDF read diverge between call sites
    /// (audit, 2026-08-17). Takes a Bool rather than the sort enum
    /// because that enum is a view-layer type and this is the only part
    /// of the rule worth sharing.
    public static func isOrderedBefore(
        _ lhs: (recency: Date, name: String),
        _ rhs: (recency: Date, name: String),
        byRecency: Bool
    ) -> Bool {
        if byRecency, lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

/// Which library rows point at which others.
public enum LibraryReferences {
    /// The names of meals that hold any of these foods — sorted, unique.
    ///
    /// Behind the delete confirmation, which warns before a food
    /// vanishes out of meals that were built from it. Worth testing
    /// rather than eyeballing: a wrong answer here degrades to a warning
    /// that is quietly incorrect rather than to a crash, so nothing else
    /// would catch it. An item whose food is already nil counts for
    /// nothing — it references no food to lose.
    public static func mealNames(
        referencing foodIDs: Set<PersistentIdentifier>, in meals: [Meal]
    ) -> [String] {
        Set(
            meals
                .filter { meal in
                    meal.items.contains { item in
                        item.food.map { foodIDs.contains($0.persistentModelID) } ?? false
                    }
                }
                .map(\.name)
        ).sorted()
    }
}

extension Food: LibrarySearchable {
    public var searchName: String { name }
    public var searchCategory: String? { category }
    public var isStarred: Bool { isFavorite }
    public var isMealRow: Bool { false }
    public var isHistoryRow: Bool { false }
    public var searchRecency: Date { recencyDate }
}

extension Meal: LibrarySearchable {
    public var searchName: String { name }
    public var searchCategory: String? { category }
    public var isStarred: Bool { isFavorite }
    public var isMealRow: Bool { true }
    public var isHistoryRow: Bool { false }
    public var searchRecency: Date { recencyDate }
}
