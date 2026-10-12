/// The frontmatter a note gets when it's converted to a task, project or area. The body is untouched.
public enum NoteConversion {
    /// The keys converting writes, in order: `type`, `status` (not for an area), the parent's link (a task's project or
    /// area, a project's area), and `createdDate` unless the note has one.
    public static func keys(to kind: Item.Kind, status: Status, parent: Parent?, createdDate: LocalDate?,
                            today: LocalDate) -> [(key: String, value: PropertyValue)] {
        var keys: [(key: String, value: PropertyValue)] = [("type", .text(kind.rawValue))]
        if kind != .area { keys.append(("status", .text(status.rawValue))) }
        switch (kind, parent) {
        case let (.task, .project(title)?): keys.append(("project", .link(title: title)))
        case let (.task, .area(title)?), let (.project, .area(title)?): keys.append(("area", .link(title: title)))
        default: break
        }
        if createdDate == nil { keys.append(("createdDate", .date(today))) }
        return keys
    }

    /// The note's text as `kind`: missing keys go straight after the opening `---` (a note without frontmatter gets the
    /// block), keys it already has are set in place, and a `project` or `area` key the parent doesn't name is emptied. A
    /// Done or Cancelled status also sets `completedDate`; any other empties it.
    public static func text(_ text: String, to kind: Item.Kind, status: Status, parent: Parent?, today: LocalDate) -> String {
        let createdDate = Item(parsing: text, path: "Note.md")?.properties.createdDate
        let keys = keys(to: kind, status: status, parent: parent, createdDate: createdDate, today: today)
        var result = FrontmatterEditor.insertAtTop(keys.filter { !FrontmatterEditor.contains($0.key, in: text) }, in: text)
        for (key, value) in keys where FrontmatterEditor.contains(key, in: text) {
            result = FrontmatterEditor.set(key, to: value, in: result)
        }
        for key in ["project", "area"] where !keys.contains(where: { $0.key == key }) {
            result = FrontmatterEditor.clear(key, in: result)
        }
        if kind != .area { result = Completion.setStatus(status, in: result, today: today) }
        return result
    }
}
