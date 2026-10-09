import Foundation

/// The link menu's matching: a title that starts with the query, then one with a word that does, then one that
/// contains it, ignoring case and diacritics.
public enum LinkSearch {
    /// The candidates that match `query`, best first, keeping their order within each rank. All of them, in order,
    /// when the query is empty.
    public static func rank<T>(_ candidates: [T], query: String, name: (T) -> String) -> [T] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return candidates }
        let ranked = candidates.enumerated().compactMap { index, candidate -> (rank: Int, index: Int, candidate: T)? in
            rank(of: name(candidate), for: query).map { ($0, index, candidate) }
        }
        return ranked.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.candidate)
    }

    private static func rank(of name: String, for query: String) -> Int? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if name.range(of: query, options: options.union(.anchored)) != nil { return 0 }
        if name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .contains(where: { $0.range(of: query, options: options.union(.anchored)) != nil }) { return 1 }
        if name.range(of: query, options: options) != nil { return 2 }
        return nil
    }
}
