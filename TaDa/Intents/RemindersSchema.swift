// The Reminders assistant schema (macOS and iOS 27): Siri treats Ta Da as a list app, so "add … to Ta Da" and
// "mark … as done in Ta Da" take any title. Tasks are reminders; projects, areas and Loose are lists. Ta Da has no flags,
// images, sections or location triggers: those are accepted and left out.
import AppIntents
import Foundation
import GeoToolbox
import TaDaCore
import UniformTypeIdentifiers

@available(macOS 27, iOS 27, *)
@AppEnum(schema: .reminders.listType)
nonisolated enum ReminderListType: String {
    case standard

    static let caseDisplayRepresentations: [ReminderListType: DisplayRepresentation] = [.standard: "List"]
}

@available(macOS 27, iOS 27, *)
@AppEnum(schema: .reminders.locationTriggerEvent)
nonisolated enum ReminderLocationEvent: String {
    case arrive, depart

    static let caseDisplayRepresentations: [ReminderLocationEvent: DisplayRepresentation] = [
        .arrive: "Arrive",
        .depart: "Depart",
    ]
}

/// A project or area, by path; Loose has the empty path.
@available(macOS 27, iOS 27, *)
@AppEntity(schema: .reminders.list)
struct ReminderListEntity {
    static let defaultQuery = ReminderListQuery()

    let id: String
    var name: String
    var type: ReminderListType

    init(id: String, name: String) {
        self.id = id
        self.name = name
        type = .standard
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// Ta Da has no sections; the query finds none.
@available(macOS 27, iOS 27, *)
@AppEntity(schema: .reminders.section)
struct ReminderSectionEntity {
    static let defaultQuery = ReminderSectionQuery()

    let id: String
    var name: String
    var list: ReminderListEntity

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// Ta Da has no location triggers; the query finds none.
@available(macOS 27, iOS 27, *)
@AppEntity(schema: .reminders.locationTrigger)
struct ReminderLocationEntity {
    static let defaultQuery = ReminderLocationQuery()

    let id: String
    var place: PlaceDescriptor
    var event: ReminderLocationEvent

    var displayRepresentation: DisplayRepresentation { "Location" }
}

/// A task, by path.
@available(macOS 27, iOS 27, *)
@AppEntity(schema: .reminders.reminder)
struct ReminderTaskEntity {
    static let defaultQuery = ReminderTaskQuery()

    let id: String
    var title: String
    var note: AttributedString?
    var tags: Set<String>
    var urls: [URL]
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var isCompleted: Bool
    var isFlagged: Bool?
    var creationDate: Date?
    var completionDate: Date?
    var list: ReminderListEntity
    var locationTrigger: ReminderLocationEntity?

    init(id: String, title: String, note: String?, tags: Set<String>, dueDate: LocalDate?, recurrence: RepeatRule?,
         isCompleted: Bool, creationDate: LocalDate?, completionDate: LocalDate?, list: ReminderListEntity) {
        self.id = id
        self.title = title
        self.note = note.map { AttributedString($0) }
        self.tags = tags
        urls = []
        self.dueDate = dueDate.map { DateComponents(year: $0.year, month: $0.month, day: $0.day) }
        self.recurrence = recurrence.flatMap(Calendar.RecurrenceRule.init)
        self.isCompleted = isCompleted
        isFlagged = nil
        self.creationDate = creationDate?.date()
        self.completionDate = completionDate?.date()
        self.list = list
        locationTrigger = nil
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

@available(macOS 27, iOS 27, *)
struct ReminderListQuery: EntityStringQuery {
    @Dependency private var model: AppModel

    func entities(for identifiers: [String]) async throws -> [ReminderListEntity] {
        await model.reminderLists().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ReminderListEntity] {
        await model.reminderLists().filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [ReminderListEntity] {
        await model.reminderLists()
    }
}

@available(macOS 27, iOS 27, *)
struct ReminderTaskQuery: EntityStringQuery {
    @Dependency private var model: AppModel

    func entities(for identifiers: [String]) async throws -> [ReminderTaskEntity] {
        await model.reminders(identifiers)
    }

    func entities(matching string: String) async throws -> [ReminderTaskEntity] {
        await model.reminders(matching: string)
    }

    func suggestedEntities() async throws -> [ReminderTaskEntity] {
        await model.reminders(matching: nil)
    }
}

@available(macOS 27, iOS 27, *)
struct ReminderSectionQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ReminderSectionEntity] { [] }
    func entities(matching string: String) async throws -> [ReminderSectionEntity] { [] }
}

@available(macOS 27, iOS 27, *)
struct ReminderLocationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ReminderLocationEntity] { [] }
    func entities(matching string: String) async throws -> [ReminderLocationEntity] { [] }
}

@available(macOS 27, iOS 27, *)
@AppIntent(schema: .reminders.createReminder)
struct AddReminderIntent {
    /// For Siri only: Shortcuts and Spotlight offer Add Task and Complete Task.
    static let isDiscoverable = false

    var title: String
    var list: ReminderListEntity?
    var note: AttributedString?
    var isFlagged: Bool?
    var images: [IntentFile]
    var tags: Set<String>
    var urls: [URL]
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var locationTrigger: ReminderLocationEntity?
    var section: ReminderSectionEntity?

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some ReturnsValue<ReminderTaskEntity> {
        let body = ([note.map { String($0.characters) }] + urls.map(\.absoluteString)).compactMap { $0 }
        let item = try await model.addTask(title, in: model.parent(ofList: list?.id), due: dueDate.flatMap(LocalDate.init),
                                           tags: tags.sorted(), repeating: recurrence.flatMap(RepeatRule.init),
                                           note: body.isEmpty ? nil : body.joined(separator: "\n"))
        return .result(value: model.reminder(item))
    }
}

@available(macOS 27, iOS 27, *)
@AppIntent(schema: .reminders.updateReminder)
struct UpdateReminderIntent {
    /// For Siri only: Shortcuts and Spotlight offer Add Task and Complete Task.
    static let isDiscoverable = false

    var target: ReminderTaskEntity
    var title: String?
    var note: AttributedString?
    var tags: Set<String>?
    var urls: [URL]?
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var isCompleted: Bool?
    var isFlagged: Bool?
    var list: ReminderListEntity?
    var locationTrigger: ReminderLocationEntity?

    @Dependency private var model: AppModel

    /// Sets what was given; the note and URLs are left, so the task's body is never replaced.
    @MainActor
    func perform() async throws -> some ReturnsValue<ReminderTaskEntity> {
        var path = try await model.intentItem(target.id, title: target.title).path
        if let isCompleted { await model.setStatus(isCompleted ? .done : .notStarted, in: path) }
        if let dueDate { await model.setDate(.due, to: LocalDate(dueDate), of: [path]) }
        if let recurrence { await model.setRepeat(RepeatRule(recurrence), of: [path]) }
        if let list { await model.setParent(list.id.isEmpty ? nil : model.index[list.id], of: [path]) }
        if let tags { await model.setTags(tags, of: path) }
        if let title { path = try await model.renameTask(path, to: title) }
        guard let item = model.index[path] else { throw IntentError.notFound(target.title) }
        return .result(value: model.reminder(item))
    }
}

@available(macOS 27, iOS 27, *)
extension AppModel {
    func reminderList(_ item: Item?) -> ReminderListEntity {
        ReminderListEntity(id: item?.path ?? "", name: item?.title ?? "Loose")
    }

    func reminder(_ item: Item) -> ReminderTaskEntity {
        let p = item.properties
        return ReminderTaskEntity(id: item.path, title: item.title, note: item.summary, tags: Set(item.tags.map(\.tag.name)),
                                  dueDate: p.dueDate, recurrence: p.repeatRule?.rule, isCompleted: p.status.isClosed,
                                  creationDate: p.createdDate, completionDate: p.completedDate,
                                  list: reminderList(index.parent(of: item)))
    }

    /// Loose, then the areas and open projects.
    func reminderLists() async -> [ReminderListEntity] {
        guard await ready() else { return [] }
        return [reminderList(nil)] + openParentEntities.compactMap { index[$0.id] }.map(reminderList)
    }

    func reminders(_ paths: [String]) async -> [ReminderTaskEntity] {
        guard await ready() else { return [] }
        return paths.compactMap { index[$0] }.filter { $0.properties.kind == .task }.map(reminder)
    }

    /// Tasks that aren't logged whose title contains `text`, or the open ones.
    func reminders(matching text: String?) async -> [ReminderTaskEntity] {
        guard await ready() else { return [] }
        guard let text else { return openTaskEntities.compactMap { index[$0.id] }.map(reminder) }
        return index.tasks.filter { $0.title.localizedStandardContains(text) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map(reminder)
    }

    /// The parent a list stands for: nil for Loose or a list that's gone.
    func parent(ofList id: String?) -> Parent? {
        guard let id, let item = index[id] else { return nil }
        return item.properties.kind == .area ? .area(item.title) : .project(item.title)
    }

    /// Makes the task's tags `names`: adds the missing ones and removes the rest.
    func setTags(_ names: Set<String>, of path: String) async {
        guard let item = index[path] else { return }
        let wanted = names.compactMap(Tag.init).filter { Tag.isValidName($0.name) }
        let current = item.tags.map(\.tag)
        for tag in current where !wanted.contains(where: { $0.path == tag.path }) { await removeTag(tag, from: path) }
        for tag in wanted where !current.contains(where: { $0.path == tag.path }) { await addTag(tag, to: path) }
    }

    /// Renames a task and returns its new path.
    func renameTask(_ path: String, to title: String) async throws -> String {
        await rename(path, to: title)
        guard index[path] == nil else { return path }
        let folder = Vault.folder(of: path)
        guard let item = index.items(titled: title).first(where: { Vault.folder(of: $0.path) == folder }) else {
            throw IntentError.notFound(title)
        }
        return item.path
    }
}

nonisolated extension LocalDate {
    /// The date in `components`, when it has a year, month and day.
    init?(_ components: DateComponents) {
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        self.init(year: year, month: month, day: day)
    }
}

/// Ta Da's repeat rules and Foundation's recurrence rules, for what both can say: the frequency, interval, weekdays of a
/// weekly rule and an end date.
nonisolated extension RepeatRule {
    init?(_ rule: Calendar.RecurrenceRule) {
        let frequency: Frequency
        switch rule.frequency {
        case .daily: frequency = .day
        case .weekly: frequency = .week
        case .monthly: frequency = .month
        case .yearly: frequency = .year
        default: return nil
        }
        let weekdays = rule.weekdays.compactMap { weekday -> Int? in
            guard case let .every(day) = weekday else { return nil }
            return Self.calendarWeekdays.firstIndex(of: day).map { $0 + 1 }
        }
        self.init(frequency: frequency, interval: rule.interval, weekdays: Set(weekdays),
                  until: rule.end.date.map { LocalDate($0) })
    }

    static let calendarWeekdays: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
}

nonisolated extension Calendar.RecurrenceRule {
    init?(_ rule: RepeatRule) {
        let frequency: Frequency
        switch rule.frequency {
        case .day: frequency = .daily
        case .weekday: frequency = .weekly
        case .week: frequency = .weekly
        case .month: frequency = .monthly
        case .year: frequency = .yearly
        }
        let weekdays = rule.frequency == .weekday ? Array(2...6) : rule.weekdays.sorted()
        self.init(calendar: .current, frequency: frequency, interval: rule.interval,
                  end: rule.until.map { .afterDate($0.date()) } ?? .never,
                  weekdays: weekdays.map { .every(RepeatRule.calendarWeekdays[$0 - 1]) })
    }
}
