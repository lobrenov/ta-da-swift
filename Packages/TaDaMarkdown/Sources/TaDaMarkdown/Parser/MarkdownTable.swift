//
//  MarkdownTable.swift
//  TaDaMarkdown
//
//  Ta Da fork: a GFM table as cells, and back to padded markdown. Cells hold
//  `\n` where the file has `<br>` and an unescaped `|` where it has `\|`.
//  Row indices count the header as row 0.
//

import Foundation

struct MarkdownTable: Equatable {

    enum Alignment: Equatable {
        /// `---`: no marker. Draws like `.left`.
        case none
        case left
        case center
        case right
    }

    var header: [String]
    var alignments: [Alignment]
    var rows: [[String]]

    var columnCount: Int { alignments.count }
    /// The header plus the body rows.
    var rowCount: Int { 1 + rows.count }

    func cell(row: Int, column: Int) -> String {
        row == 0 ? header[column] : rows[row - 1][column]
    }

    // MARK: - Parsing

    /// Ragged rows are padded (or cut) to the wider of the header and the delimiter row.
    static func parse(_ source: String) -> MarkdownTable? {
        let lines = source.components(separatedBy: CharacterSet.newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return nil }

        let header = parseRow(lines[0])
        let alignments = parseAlignments(lines[1])
        guard !header.isEmpty, !alignments.isEmpty else { return nil }

        let columnCount = max(header.count, alignments.count)
        func pad<T>(_ array: [T], with fill: T) -> [T] {
            array.count >= columnCount
                ? Array(array.prefix(columnCount))
                : array + Array(repeating: fill, count: columnCount - array.count)
        }
        return MarkdownTable(
            header: pad(header, with: ""),
            alignments: pad(alignments, with: .none),
            rows: lines.dropFirst(2).map { pad(parseRow($0), with: "") }
        )
    }

    /// Splits on UNESCAPED `|` only. GFM escapes the delimiter as `\|`, and
    /// the escape wins over every inline context (a table row is split before
    /// inline parsing runs), so a cell holding `` `a \| b` `` is one cell.
    private static func parseRow(_ line: String) -> [String] {
        var s = Substring(line.trimmingCharacters(in: .whitespaces))
        if s.hasPrefix("|") { s = s.dropFirst() }
        if s.hasSuffix("|"), !s.dropLast().hasSuffix("\\") { s = s.dropLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for ch in s {
            if escaped {
                // Only the delimiter escape is resolved here; every other `\x`
                // stays intact so inline parsing still owns its own escapes.
                if ch == "|" { current.append("|") } else { current.append("\\"); current.append(ch) }
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                cells.append(finishCell(current))
                current = ""
            } else {
                current.append(ch)
            }
        }
        if escaped { current.append("\\") }
        cells.append(finishCell(current))
        return cells
    }

    private static func finishCell(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(
            of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func parseAlignments(_ line: String) -> [Alignment] {
        parseRow(line).map { cell in
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): return .center
            case (true, false): return .left
            case (false, true): return .right
            default: return .none
            }
        }
    }

    // MARK: - Writing

    /// The table's lines, columns padded to line up, without a trailing newline.
    var markdown: String {
        let escaped = ([header] + rows).map { $0.map(Self.escape) }
        let widths = (0..<columnCount).map { column in
            max(3, escaped.map { $0[column].count }.max() ?? 0)
        }
        func line(_ cells: [String]) -> String {
            "| " + zip(cells, widths).map { $0 + String(repeating: " ", count: $1 - $0.count) }
                .joined(separator: " | ") + " |"
        }
        let delimiter = zip(alignments, widths).map { alignment, width -> String in
            switch alignment {
            case .none: return String(repeating: "-", count: width)
            case .left: return ":" + String(repeating: "-", count: width - 1)
            case .right: return String(repeating: "-", count: width - 1) + ":"
            case .center: return ":" + String(repeating: "-", count: width - 2) + ":"
            }
        }
        return ([line(escaped[0]), line(delimiter)] + escaped.dropFirst().map(line)).joined(separator: "\n")
    }

    private static func escape(_ cell: String) -> String {
        cell.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>")
    }

    // MARK: - Editing

    mutating func setCell(row: Int, column: Int, to text: String) {
        if row == 0 { header[column] = text } else { rows[row - 1][column] = text }
    }

    /// A blank row at `index` (0...rowCount). At 0 it becomes the header.
    mutating func insertRow(at index: Int) {
        let blank = [String](repeating: "", count: columnCount)
        if index == 0 {
            rows.insert(header, at: 0)
            header = blank
        } else {
            rows.insert(blank, at: index - 1)
        }
    }

    /// Deleting the header makes the next row the header. The only row stays:
    /// the caller removes the whole table.
    mutating func deleteRow(at index: Int) {
        guard rowCount > 1 else { return }
        if index == 0 { header = rows.removeFirst() } else { rows.remove(at: index - 1) }
    }

    /// Moves a body row so it ends at `destination`. The header can't move and
    /// nothing moves above it.
    mutating func moveRow(from index: Int, to destination: Int) {
        guard index > 0 else { return }
        let target = min(max(destination, 1), rowCount - 1)
        rows.insert(rows.remove(at: index - 1), at: target - 1)
    }

    mutating func insertColumn(at index: Int) {
        header.insert("", at: index)
        alignments.insert(.none, at: index)
        for i in rows.indices { rows[i].insert("", at: index) }
    }

    /// The only column stays: the caller removes the whole table.
    mutating func deleteColumn(at index: Int) {
        guard columnCount > 1 else { return }
        header.remove(at: index)
        alignments.remove(at: index)
        for i in rows.indices { rows[i].remove(at: index) }
    }

    mutating func moveColumn(from index: Int, to destination: Int) {
        let target = min(max(destination, 0), columnCount - 1)
        func move<T>(_ array: inout [T]) { array.insert(array.remove(at: index), at: target) }
        move(&header)
        move(&alignments)
        for i in rows.indices { move(&rows[i]) }
    }

    mutating func setAlignment(_ alignment: Alignment, column: Int) {
        alignments[column] = alignment
    }
}
