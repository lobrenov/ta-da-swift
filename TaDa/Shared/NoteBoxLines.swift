// A note's checkbox lines, for the iPhone Agenda's inline note card.
import Foundation
import TaDaCore

nonisolated struct NoteBoxLine: Hashable, Sendable {
    enum State { case open, doing, done }

    let text: String
    let state: State

    /// How many lines a card shows at most.
    static let limit = 6

    /// How many lines the card of a note with these checkboxes shows, before they're read.
    static func count(of checkboxes: [Checkbox]) -> Int {
        min(limit, checkboxes.count { $0.state == .open || $0.state == .done })
    }

    /// The open and done checkbox lines of `text` that `checkboxes` locate, in order, up to `limit`.
    static func lines(in text: String, boxes checkboxes: [Checkbox]) -> [NoteBoxLine] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [NoteBoxLine] = []
        for box in checkboxes where result.count < limit && lines.indices.contains(box.lineIndex) {
            let state: State
            switch box.state {
            case .open: state = box.marker == "/" ? .doing : .open
            case .done: state = .done
            case .cancelled, .icon: continue
            }
            let bytes = Array(lines[box.lineIndex].utf8)
            // The marker, then the closing bracket.
            guard bytes.count >= box.column + 2 else { continue }
            let label = String(decoding: bytes[(box.column + 2)...], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(NoteBoxLine(text: label, state: state))
        }
        return result
    }
}
