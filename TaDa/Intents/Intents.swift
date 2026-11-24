// The actions Ta Da gives Shortcuts and Siri: add a task, complete one, open a task, project or area, and show a view.
import AppIntents
import Foundation
import TaDaCore

nonisolated enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noFolder
    case notFound(String)
    case notCreated

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noFolder: "Open a folder in Ta Da first."
        case let .notFound(title): "“\(title)” isn’t in the open folder."
        case .notCreated: "Ta Da couldn’t create the task."
        }
    }
}

extension AppModel {
    /// The open folder's item at `path`, opening the folder first if the app has just launched.
    func intentItem(_ path: String, title: String) async throws -> Item {
        guard await ready() else { throw IntentError.noFolder }
        guard let item = index[path] else { throw IntentError.notFound(title) }
        return item
    }

    /// Adds a task to the open folder as Quick Entry would, with tags whose names are valid and `note` as its body.
    func addTask(_ title: String, in parent: Parent?, due: LocalDate?, tags: [String], repeating rule: RepeatRule? = nil,
                 note: String? = nil) async throws -> Item {
        guard await ready() else { throw IntentError.noFolder }
        var draft = QuickEntryDraft()
        draft.title = title
        draft.parent = parent
        draft.dueDate = due
        draft.repeatText = rule.map { $0.anchored(to: due ?? today).phrase }
        draft.tags = tags.compactMap(Tag.init).filter { Tag.isValidName($0.name) }
        guard let path = await create(draft) else { throw IntentError.notCreated }
        if let note, !note.isEmpty { await edit(path) { $0 + note + "\n" } }
        guard let item = index[path] else { throw IntentError.notCreated }
        return item
    }
}

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription("Adds a task to the open folder.")

    @Parameter(title: "Title", requestValueDialog: "What’s the task called?")
    var title: String
    @Parameter(title: "Project or Area")
    var parent: ParentEntity?
    @Parameter(title: "Due Date", kind: .date)
    var dueDate: Date?
    @Parameter(title: "Tags")
    var tags: [String]?

    @Dependency private var model: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$title) to \(\.$parent)") {
            \.$dueDate
            \.$tags
        }
    }

    @MainActor
    func perform() async throws -> some ReturnsValue<TaskEntity> & ProvidesDialog {
        let item = try await model.addTask(title, in: parent?.parent, due: dueDate.map { LocalDate($0) }, tags: tags ?? [])
        return .result(value: model.taskEntity(item), dialog: "Added “\(item.title)”")
    }
}

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription("Marks a task Done.")

    @Parameter(title: "Task")
    var task: TaskEntity

    @Dependency private var model: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let item = try await model.intentItem(task.id, title: task.title)
        guard !item.properties.status.isClosed else { return .result(dialog: "“\(item.title)” is already \(item.properties.status.rawValue).") }
        await model.setStatus(.done, in: item.path)
        return .result(dialog: "Completed “\(item.title)”")
    }
}

struct OpenTaskIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Task"

    @Parameter(title: "Task")
    var target: TaskEntity

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        let item = try await model.intentItem(target.id, title: target.title)
        model.reveal(.file(item.path))
        return .result()
    }
}

struct OpenParentIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Project or Area"

    @Parameter(title: "Project or Area")
    var target: ParentEntity

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        let item = try await model.intentItem(target.id, title: target.title)
        model.reveal(.file(item.path))
        return .result()
    }
}

/// The views Show can open.
nonisolated enum ShownView: String, AppEnum {
    case agenda, loose, logbook

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "View"
    static let caseDisplayRepresentations: [ShownView: DisplayRepresentation] = [
        .agenda: "Agenda",
        .loose: "Loose Tasks",
        .logbook: "Logbook",
    ]

    var domain: AppModel.Domain {
        switch self {
        case .agenda: .agenda
        case .loose: .loose
        case .logbook: .logbook
        }
    }
}

struct ShowViewIntent: AppIntent {
    static let title: LocalizedStringResource = "Show View"
    static let description = IntentDescription("Opens Ta Da on the Agenda, Loose Tasks or the Logbook.")
    static let openAppWhenRun = true

    @Parameter(title: "View", default: .agenda)
    var view: ShownView

    @Dependency private var model: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$view)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard await model.ready() else { throw IntentError.noFolder }
        model.reveal(.domain(view.domain))
        return .result()
    }
}
