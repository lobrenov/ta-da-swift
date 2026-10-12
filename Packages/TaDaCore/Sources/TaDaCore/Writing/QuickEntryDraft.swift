/// What Quick Entry holds for a new file before it's written. The title becomes the filename.
public struct QuickEntryDraft: Equatable, Sendable {
    public var kind: Item.Kind = .task
    public var title = ""
    public var status: Status = .notStarted
    /// A task's project or area, or a project's area.
    public var parent: Parent?
    public var dueDate: LocalDate?
    public var deadline: LocalDate?
    public var tags: [Tag] = []

    public init() {}

    /// The folder the file goes in.
    public var folder: String {
        switch kind {
        case .task: Vault.taskFolder
        case .project: Vault.projectFolder
        case .area: Vault.areaFolder
        case .note: ""
        }
    }

    /// The file's text: `NewFile`'s for the kind, with the status, due date and deadline set.
    public func text(today: LocalDate) -> String {
        var text = switch kind {
        case .task:
            NewFile.task(project: parent?.projectTitle, area: parent?.areaTitle, tags: tags, today: today)
        case .project:
            NewFile.project(area: parent?.areaTitle, tags: tags, today: today)
        case .area:
            NewFile.area(tags: tags, today: today)
        case .note:
            NewFile.note(tags: tags, today: today)
        }
        guard kind != .area, kind != .note else { return text }
        if status != .notStarted { text = Completion.setStatus(status, in: text, today: today) }
        if let dueDate { text = FrontmatterEditor.set("dueDate", to: .date(dueDate), in: text) }
        if let deadline { text = FrontmatterEditor.set("deadline", to: .date(deadline), in: text) }
        return text
    }

    /// The draft as `kind`, keeping the title and tags. A project keeps only an area parent; an area keeps nothing else.
    public func changingKind(to kind: Item.Kind) -> QuickEntryDraft {
        var draft = QuickEntryDraft()
        draft.kind = kind
        draft.title = title
        draft.tags = tags
        guard kind != .area, kind != .note else { return draft }
        draft.status = Status.choices(for: kind).contains(status) ? status : .notStarted
        draft.dueDate = dueDate
        draft.deadline = deadline
        draft.parent = kind == .project && parent?.areaTitle == nil ? nil : parent
        return draft
    }
}

private extension Parent {
    var projectTitle: String? { if case let .project(title) = self { title } else { nil } }
    var areaTitle: String? { if case let .area(title) = self { title } else { nil } }
}
