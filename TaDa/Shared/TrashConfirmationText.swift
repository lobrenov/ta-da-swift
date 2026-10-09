// The delete confirmation's title and message, for deleting an area, and the words of the dialog that lists the
// images the files embed (`DeleteFilesDialog.swift`).
import TaDaCore

/// What the delete confirmation says about `model.trashConfirmation`.
struct TrashConfirmationText {
    let model: AppModel
    /// The request it describes: `model.trashConfirmation` unless a dialog that outlives it passes its own.
    let request: AppModel.TrashConfirmation?

    init(model: AppModel, request: AppModel.TrashConfirmation? = nil) {
        self.model = model
        self.request = request ?? model.trashConfirmation
    }

    private var items: [Item] { request?.items ?? [] }

    var title: String {
        items.count == 1 ? "Delete “\(items[0].title)”?" : "Delete \(items.count) files?"
    }

    /// For one area: what goes with it, and what a restore brings back. Otherwise the number of files.
    var message: String {
        guard items.count == 1, let area = items.first, area.properties.kind == .area else {
            return "\(request?.count ?? 0) files move to the Trash, with everything in the areas."
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

    /// "“Sell the Kombi” and its 3 tasks", "“Photograph the Kombi”", "2 tasks" or "5 files".
    var subject: String {
        let total = request?.count ?? 0
        guard items.count == 1, let item = items.first else {
            return items.allSatisfy { $0.properties.kind == .task } ? count(items.count, "task") : count(total, "file")
        }
        let taken = total - 1
        return switch item.properties.kind {
        case _ where taken == 0: "“\(item.title)”"
        case .project: "“\(item.title)” and its \(count(taken, "task"))"
        default: "“\(item.title)” and its \(count(taken, "file"))"
        }
    }

    /// The images dialog's explanation: the Mac's, or (`phone`) the iPhone's.
    func imagesMessage(phone: Bool) -> String {
        let one = request?.count == 1
        return phone
            ? "Ticked attachments go with \(one ? "it" : "them"). Ones that other files still embed start unticked."
            : "\(one ? "The file goes" : "The files go") to Trash with the attachments ticked below. Attachments that other files still embed start unticked."
    }

    /// "4 files and 3 of 5 attachments go to Trash. Restore brings them back together."
    func imagesSummary(ticked: Int, phone: Bool) -> String {
        let total = request?.images.reduce(0) { $0 + $1.images.count } ?? 0
        return "\(count(request?.count ?? 0, "file")) and \(ticked) of \(count(total, "attachment"))"
            + (phone ? "" : " go to Trash") + ". Restore brings them back together."
    }

    /// Under an image: the other files that embed it, as text before, in and after the link colour.
    static func note(for image: AppModel.TrashImage, ticked: Bool, phone: Bool) -> (before: String, titles: String, after: String) {
        if !image.keptIn.isEmpty {
            return ("Also in ", image.keptIn.joined(separator: ", "), ticked ? ", which will show it as broken" : "")
        }
        if !image.goingIn.isEmpty { return ("Also in ", image.goingIn.joined(separator: ", "), phone ? ", moving too" : ", deleted too") }
        return ("Not embedded anywhere else", "", "")
    }

    private func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }
}
