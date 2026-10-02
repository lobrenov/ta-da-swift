/// The text of a file Ta Da creates. The title isn't written: it's the filename.
public enum NewFile {
    public static func task(project: String? = nil, today: LocalDate) -> String {
        var keys = ["type: task", "status: Not Started"]
        if let project { keys.append("project: \(FrontmatterEditor.quoted("[[\(project)]]"))") }
        keys.append("createdDate: \(today)")
        return block(keys)
    }

    public static func project(today: LocalDate) -> String {
        block(["type: project", "status: Not Started", "createdDate: \(today)"])
    }

    private static func block(_ keys: [String]) -> String {
        (["---"] + keys + ["---", ""]).joined(separator: "\n")
    }
}
