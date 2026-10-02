/// Filenames from titles. The title is the filename without `.md`.
public enum FileNaming {
    /// Replaces characters that are invalid in filenames or break Obsidian links.
    /// `:` becomes ` -`, `/ \ |` become `-`, and `* ? " < > [ ] # ^` are dropped.
    /// Leading dots (hidden files) and repeated spaces go; the result fits in 200 UTF-8 bytes.
    public static func sanitise(_ title: String) -> String {
        var name = ""
        for character in title {
            switch character {
            case ":": name += " -"
            case "/", "\\", "|": name += "-"
            case "*", "?", "\"", "<", ">", "[", "]", "#", "^": break
            case _ where character.isNewline || character == "\t": name += " "
            default: name.append(character)
            }
        }
        name = name.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingWhitespace()
        while name.utf8.count > 200 { name.removeLast() }
        name = name.trimmingWhitespace()
        return name.isEmpty ? "Untitled" : name
    }

    /// `<title>.md`, or `<title> 2.md`, `<title> 3.md`… when the name is taken.
    /// `existing` holds filenames in the target folder; matching ignores case, like APFS.
    public static func filename(for title: String, existing: Set<String>) -> String {
        let base = sanitise(title)
        let taken = Set(existing.map { $0.lowercased() })
        var candidate = "\(base).md"
        var number = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(base) \(number).md"
            number += 1
        }
        return candidate
    }
}

private extension String {
    func trimmingWhitespace() -> String {
        String(drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
