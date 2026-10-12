/// The text of a file Ta Da creates. The title isn't written: it's the filename. Tags go in `tags:` as a flow list.
public enum NewFile {
    /// A task names one parent: its project, or else its area.
    public static func task(project: String? = nil, area: String? = nil, tags: [Tag] = [], today: LocalDate) -> String {
        var keys = ["type: task", "status: Not Started"]
        if let project {
            keys.append("project: \(FrontmatterEditor.quoted("[[\(project)]]"))")
        } else if let area {
            keys.append("area: \(FrontmatterEditor.quoted("[[\(area)]]"))")
        }
        keys.append("createdDate: \(today)")
        return block(keys, tags: tags)
    }

    public static func project(area: String? = nil, tags: [Tag] = [], today: LocalDate) -> String {
        var keys = ["type: project", "status: Not Started"]
        if let area { keys.append("area: \(FrontmatterEditor.quoted("[[\(area)]]"))") }
        keys.append("createdDate: \(today)")
        return block(keys, tags: tags)
    }

    public static func area(tags: [Tag] = [], today: LocalDate) -> String {
        block(["type: area", "createdDate: \(today)"], tags: tags)
    }

    /// A note always gets `tags:`, `[]` when there are none.
    public static func note(tags: [Tag] = [], today: LocalDate) -> String {
        tags.isEmpty ? block(["createdDate: \(today)", "tags: []"], tags: []) : block(["createdDate: \(today)"], tags: tags)
    }

    private static func block(_ keys: [String], tags: [Tag]) -> String {
        var keys = keys
        if !tags.isEmpty { keys.append("tags: [\(tags.unique.map { FrontmatterEditor.flowItem($0.name) }.joined(separator: ", "))]") }
        return (["---"] + keys + ["---", ""]).joined(separator: "\n")
    }
}
