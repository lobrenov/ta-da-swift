/// Reads `#tags` from a run of body text, as Obsidian does: `#` at the run's start (when that's a boundary) or after
/// whitespace, then letters, digits, `_`, `-` and `/`, with at least one character that isn't a digit. Any other
/// character ends the tag. `[[…]]` links are skipped, so `[[Note #Heading]]` holds no tag.
enum InlineTags {
    /// - Parameter atBoundary: whether the text starts a line or follows whitespace.
    static func scan(_ text: String, atBoundary: Bool) -> [Tag] {
        let chars = Array(text)
        var tags: [Tag] = []
        var boundary = atBoundary
        var i = 0
        while i < chars.count {
            if let end = linkEnd(chars, at: i) {
                boundary = false
                i = end
                continue
            }
            if chars[i] == "#", boundary {
                var end = i + 1
                while end < chars.count, isTagCharacter(chars[end]) { end += 1 }
                let raw = chars[(i + 1)..<end]
                if raw.contains(where: { !$0.isNumber && $0 != "/" }), let tag = Tag(String(raw)) { tags.append(tag) }
                boundary = false
                i = end
                continue
            }
            boundary = chars[i].isWhitespace
            i += 1
        }
        return tags
    }

    static func isTagCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "-" || c == "/"
    }

    /// The index after a `[[…]]` starting at `i` (with an optional `!`), as `WikiLink.scan` matches them; nil if none.
    private static func linkEnd(_ chars: [Character], at i: Int) -> Int? {
        var j = chars[i] == "!" ? i + 1 : i
        guard j + 1 < chars.count, chars[j] == "[", chars[j + 1] == "[" else { return nil }
        j += 2
        let start = j
        while j < chars.count, !"[]\n".contains(chars[j]) { j += 1 }
        guard j > start, j + 1 < chars.count, chars[j] == "]", chars[j + 1] == "]" else { return nil }
        return j + 2
    }
}
