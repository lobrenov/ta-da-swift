// The delete confirmation's title and message, for deleting an area.
import TaDaCore

/// What the delete confirmation says about `model.trashConfirmation`.
struct TrashConfirmationText {
    let model: AppModel

    private var items: [Item] { model.trashConfirmation?.paths.compactMap { model.index[$0] } ?? [] }

    var title: String {
        items.count == 1 ? "Delete “\(items[0].title)”?" : "Delete \(items.count) files?"
    }

    /// For one area: what goes with it, and what a restore brings back. Otherwise the number of files.
    var message: String {
        guard items.count == 1, let area = items.first, area.properties.kind == .area else {
            return "\(model.trashConfirmation?.count ?? 0) files move to the Trash, with everything in the areas."
        }
        let index = model.index
        let projects = index.projects(in: area)
        let projectTasks = projects.reduce(0) { $0 + index.tasks(in: $1).count }
        let own = index.tasks(in: area).count
        var parts = [area.title]
        if !projects.isEmpty {
            parts.append("its \(count(projects.count, "project"))" + (projectTasks > 0 ? " and their \(count(projectTasks, "task"))" : ""))
        }
        if own > 0 { parts.append("its \(count(own, "own task"))") }
        let list = parts.count > 2 ? parts.dropLast().joined(separator: ", ") + ", and " + parts.last! : parts.joined(separator: " and ")
        return "\(list) \(parts.count == 1 ? "moves" : "move") to the Trash.\n\nRestoring \(area.title) brings back the area alone. "
            + "Restoring a project or task brings \(area.title) back with it."
    }

    private func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }
}
