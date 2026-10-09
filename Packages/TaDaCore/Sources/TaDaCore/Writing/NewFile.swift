/// The text of a file Ta Da creates. The title isn't written: it's the filename.
public enum NewFile {
    /// A task names one parent: its project, or else its area.
    public static func task(project: String? = nil, area: String? = nil, today: LocalDate) -> String {
        var keys = ["type: task", "status: Not Started"]
        if let project {
            keys.append("project: \(FrontmatterEditor.quoted("[[\(project)]]"))")
        } else if let area {
            keys.append("area: \(FrontmatterEditor.quoted("[[\(area)]]"))")
        }
        keys.append("createdDate: \(today)")
        return block(keys)
    }

    public static func project(area: String? = nil, today: LocalDate) -> String {
        var keys = ["type: project", "status: Not Started"]
        if let area { keys.append("area: \(FrontmatterEditor.quoted("[[\(area)]]"))") }
        keys.append("createdDate: \(today)")
        return block(keys)
    }

    public static func area(today: LocalDate) -> String {
        block(["type: area", "createdDate: \(today)"])
    }

    private static func block(_ keys: [String]) -> String {
        (["---"] + keys + ["---", ""]).joined(separator: "\n")
    }
}
