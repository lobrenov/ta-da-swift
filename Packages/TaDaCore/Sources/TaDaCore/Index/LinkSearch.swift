import Foundation

/// The link menu's matching: a title that starts with the query, then one with a word that does, then one that
/// contains it, ignoring case and diacritics.
public enum LinkSearch {
    /// The candidates that match `query`, best first, keeping their order within each rank. All of them, in order,
    /// when the query is empty (still ordered by `then`). Within a rank, `then` orders the candidates it distinguishes, so a caller can leave the
    /// candidates unsorted and have only the matches sorted. With `limit`, only the first `limit` are returned, and only
    /// as many as that are sorted.
    public static func rank<T>(_ candidates: [T], query: String, name: (T) -> String, then: ((T, T) -> Bool)? = nil,
                               limit: Int? = nil) -> [T] {
        let query = query.trimmingCharacters(in: .whitespaces)
        var buckets: [[Int]] = [[], [], []]
        if query.isEmpty {
            buckets[0] = Array(candidates.indices)
        } else {
            let matcher = Matcher(query)
            for index in candidates.indices {
                if let rank = matcher.rank(of: name(candidates[index])) { buckets[rank].append(index) }
            }
        }
        var result: [T] = []
        for bucket in buckets where !bucket.isEmpty {
            let wanted = limit.map { $0 - result.count } ?? bucket.count
            guard wanted > 0 else { break }
            result += first(wanted, of: bucket, in: candidates, then: then)
        }
        return result
    }

    /// The first `count` of the candidates at `indices`, which arrive in input order, ordered by `then`, then input order.
    private static func first<T>(_ count: Int, of indices: [Int], in candidates: [T], then: ((T, T) -> Bool)?) -> [T] {
        guard let then else { return indices.prefix(count).map { candidates[$0] } }
        guard count < indices.count else {
            return indices.sorted { a, b in
                if then(candidates[a], candidates[b]) { return true }
                return !then(candidates[b], candidates[a]) && a < b
            }.map { candidates[$0] }
        }
        var best: [Int] = []
        for index in indices {
            // Every entry already in `best` came earlier, so a tie leaves the new one after it.
            if best.count == count, !then(candidates[index], candidates[best[count - 1]]) { continue }
            var low = 0, high = best.count
            while low < high {
                let mid = (low + high) / 2
                if then(candidates[index], candidates[best[mid]]) { high = mid } else { low = mid + 1 }
            }
            best.insert(index, at: low)
            if best.count > count { best.removeLast() }
        }
        return best.map { candidates[$0] }
    }

    /// Ranks names against one query; a plain ASCII query and name are compared with libc, anything else by Foundation.
    private struct Matcher {
        let query: String
        /// The query as a C string when it's plain ASCII.
        let ascii: [CChar]?
        /// Whether the query holds a word separator, so it can't be a word's start.
        let hasSeparator: Bool

        init(_ query: String) {
            self.query = query
            ascii = query.utf8.allSatisfy { $0 > 0 && $0 < 128 } ? query.utf8CString.map { $0 } : nil
            hasSeparator = query.utf8.contains { $0 == 32 || $0 == 45 || $0 == 95 }
        }

        func rank(of name: String) -> Int? {
            if let ascii {
                let rank = name.withCString { asciiRank(of: $0, for: ascii) }
                if rank != Self.notASCII { return rank < 0 ? nil : rank }
            }
            return foundationRank(of: name)
        }

        /// What `asciiRank` returns for a name with a byte past ASCII.
        private static let notASCII = -2

        /// The rank of `name` (-1 for none), or `notASCII`.
        private func asciiRank(of name: UnsafePointer<CChar>, for query: [CChar]) -> Int {
            let length = strlen(name)
            let highBits: UInt64 = 0x8080_8080_8080_8080
            if length >= 8 {
                var offset = 0
                while offset + 8 < length {
                    if UnsafeRawPointer(name + offset).loadUnaligned(as: UInt64.self) & highBits != 0 { return Self.notASCII }
                    offset += 8
                }
                if UnsafeRawPointer(name + length - 8).loadUnaligned(as: UInt64.self) & highBits != 0 { return Self.notASCII }
            } else {
                for offset in 0..<length where name[offset] < 0 { return Self.notASCII }
            }
            return query.withUnsafeBufferPointer { query in
                let needle = query.baseAddress!
                if strncasecmp(name, needle, query.count - 1) == 0 { return 0 }
                guard var found = strcasestr(name, needle) else { return -1 }
                if hasSeparator { return 2 }
                while true {
                    if found > name, [32, 45, 95].contains(found[-1]) { return 1 }
                    guard let next = strcasestr(found + 1, needle) else { return 2 }
                    found = UnsafeMutablePointer(mutating: next)
                }
            }
        }

        private func foundationRank(of name: String) -> Int? {
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            if name.range(of: query, options: options.union(.anchored)) != nil { return 0 }
            if name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
                .contains(where: { $0.range(of: query, options: options.union(.anchored)) != nil }) { return 1 }
            if name.range(of: query, options: options) != nil { return 2 }
            return nil
        }
    }
}
