import Foundation

/// The listed subtask lines of one file, in file order.
public struct SubtaskCard: Hashable, Sendable, Identifiable {
    public var path: String
    public var lines: [Checkbox]

    public var id: String { path }
    public var title: String { Item.title(ofPath: path) }
    public var folder: String { Vault.folder(of: path) }
}

/// Subtask lines listed outside their file (see Subtasks in `docs/file-format.md`). A line is listed when it's an open
/// box that isn't nested or quoted, in a file that isn't logged or closed, and it's in a note or carries a due date or a
/// parent that resolves. Each query returns cards by source title, then path; `today` is passed in.
extension VaultIndex {
    /// The lines due on `date`; for `today`, also those due earlier (overdue).
    public func noteSubtasks(on date: LocalDate, today: LocalDate) -> [SubtaskCard] {
        cards { _, box in
            guard let due = box.due else { return false }
            return due == date || (date == today && due < today)
        }
    }

    /// The lines due from `from` through `through`.
    public func noteSubtasks(from: LocalDate, through: LocalDate) -> [SubtaskCard] {
        cards { _, box in box.due.map { $0 >= from && $0 <= through } ?? false }
    }

    /// The lines whose parent resolves to this project or area, leaving out its own file's.
    public func noteSubtasks(parent: Item) -> [SubtaskCard] {
        cards { item, box in
            item.path != parent.path && box.parent.flatMap(parentItem(titled:))?.path == parent.path
        }
    }

    /// A note's lines with no due date and no parent that resolves.
    public func looseNoteSubtasks() -> [SubtaskCard] {
        cards { item, box in
            item.properties.kind == .note && box.due == nil && box.parent.flatMap(parentItem(titled:)) == nil
        }
    }

    /// Every project's and area's cards at once, by the parent's path, as `noteSubtasks(parent:)` gives them, in one pass.
    public func noteSubtasksByParent() -> [String: [SubtaskCard]] {
        var resolved: [String: String?] = [:]
        func path(of title: String) -> String? {
            let key = title.lowercased()
            if let known = resolved[key] { return known }
            let found = parentItem(titled: title)?.path
            resolved[key] = found
            return found
        }
        var grouped: [String: [(Item, [Checkbox])]] = [:]
        for item in items.values where !item.checkboxes.isEmpty {
            var byParent: [String: [Checkbox]] = [:]
            for box in item.checkboxes where isOpenLine(box, in: item) {
                if let parent = box.parent.flatMap(path(of:)), parent != item.path { byParent[parent, default: []].append(box) }
            }
            for (parent, lines) in byParent { grouped[parent, default: []].append((item, lines)) }
        }
        return grouped.mapValues { $0.sorted { Self.byTitle($0.0, $1.0) }.map { SubtaskCard(path: $0.0.path, lines: $0.1) } }
    }

    /// The live project a `@[[Title]]` resolves to, else the live area: the first of each by path. A logged file
    /// resolves nothing.
    public func parentItem(titled title: String) -> Item? {
        let found = items(titled: title).filter { !$0.isLogged }
        return found.first { $0.properties.kind == .project } ?? found.first { $0.properties.kind == .area }
    }

    /// Whether `box` in `item` is a listed line.
    func isListed(_ box: Checkbox, in item: Item) -> Bool {
        guard isOpenLine(box, in: item) else { return false }
        return item.properties.kind == .note || box.due != nil || box.parent.flatMap(parentItem(titled:)) != nil
    }

    /// An open box that isn't nested or quoted, in a file that isn't logged or closed.
    private func isOpenLine(_ box: Checkbox, in item: Item) -> Bool {
        box.state == .open && !box.isNested && !box.isQuoted && !item.isLogged && !item.properties.status.isClosed
    }

    private func cards(where keep: (Item, Checkbox) -> Bool) -> [SubtaskCard] {
        items.values.compactMap { item -> (Item, [Checkbox])? in
            guard !item.checkboxes.isEmpty else { return nil }
            let lines = item.checkboxes.filter { isListed($0, in: item) && keep(item, $0) }
            return lines.isEmpty ? nil : (item, lines)
        }
        .sorted { Self.byTitle($0.0, $1.0) }
        .map { SubtaskCard(path: $0.0.path, lines: $0.1) }
    }
}
