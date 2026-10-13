// The device's Calendar events and Reminders for Today and Upcoming, read through EventKit. Ta Da never writes them.
import CoreGraphics
import EventKit
import Foundation
import TaDaCore

@MainActor @Observable
final class IntegrationsStore {
    enum Kind: CaseIterable, Sendable {
        case events, reminders

        var entityType: EKEntityType { self == .events ? .event : .reminder }
    }

    /// What Settings shows for a switch.
    enum Access: Equatable { case off, asking, granted, denied }

    /// A calendar or Reminders list, with its colour as `#RRGGBB`.
    struct ListChoice: Identifiable, Hashable {
        var id: String
        var title: String
        var color: String
    }

    /// An account's calendars or lists.
    struct Source: Identifiable, Hashable {
        var id: String
        var title: String
        var calendars: [ListChoice]
    }

    // MARK: Settings

    /// Settings ▸ Integrations' switches. On only while access is granted.
    private(set) var showsEvents: Bool {
        didSet { defaults.set(showsEvents, forKey: Keys.showsEvents) }
    }
    private(set) var showsReminders: Bool {
        didSet { defaults.set(showsReminders, forKey: Keys.showsReminders) }
    }
    /// The unticked calendars and lists, so one added later shows.
    private(set) var hiddenCalendars: Set<String> {
        didSet { defaults.set(hiddenCalendars.sorted(), forKey: Keys.hiddenCalendars) }
    }
    private(set) var hiddenLists: Set<String> {
        didSet { defaults.set(hiddenLists.sorted(), forKey: Keys.hiddenLists) }
    }

    private(set) var eventStatus: EKAuthorizationStatus
    private(set) var reminderStatus: EKAuthorizationStatus
    private var asking: Set<Kind> = []

    /// The calendars and the Reminders lists, by account, while their switch is on.
    private(set) var calendarSources: [Source] = []
    private(set) var listSources: [Source] = []

    // MARK: Lists

    /// Today's events and reminders (due today or overdue), and Upcoming's by day after today.
    private(set) var todayEvents: [DayEvent] = []
    private(set) var todayReminders: [ExternalReminder] = []
    private(set) var upcomingEvents: [LocalDate: [DayEvent]] = [:]
    private(set) var upcomingReminders: [LocalDate: [ExternalReminder]] = [:]

    private let defaults: any SettingsStore
    @ObservationIgnored private var eventStore: EKEventStore?
    @ObservationIgnored private var storeObserver: (any NSObjectProtocol)?
    /// Today and the last day fetched.
    @ObservationIgnored private var window: (today: LocalDate, last: LocalDate)?
    @ObservationIgnored private var fetches = 0

    private enum Keys {
        static let showsEvents = "integrations.showsEvents"
        static let showsReminders = "integrations.showsReminders"
        static let hiddenCalendars = "integrations.hiddenCalendars"
        static let hiddenLists = "integrations.hiddenLists"
    }

    init(defaults: any SettingsStore) {
        self.defaults = defaults
        showsEvents = defaults.bool(forKey: Keys.showsEvents)
        showsReminders = defaults.bool(forKey: Keys.showsReminders)
        hiddenCalendars = Set(defaults.stringArray(forKey: Keys.hiddenCalendars) ?? [])
        hiddenLists = Set(defaults.stringArray(forKey: Keys.hiddenLists) ?? [])
        eventStatus = EKEventStore.authorizationStatus(for: .event)
        reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func isOn(_ kind: Kind) -> Bool {
        kind == .events ? showsEvents : showsReminders
    }

    /// Whether the switch is on and access is granted, so the kind shows in Today and Upcoming.
    func isShown(_ kind: Kind) -> Bool {
        isOn(kind) && status(kind) == .fullAccess
    }

    func access(_ kind: Kind) -> Access {
        if asking.contains(kind) { return .asking }
        switch status(kind) {
        case .denied, .restricted, .writeOnly: return .denied
        case .fullAccess: return isOn(kind) ? .granted : .off
        default: return .off
        }
    }

    /// Turns a switch on, first asking for full access, or off. Denied, the switch stays off.
    func setOn(_ on: Bool, _ kind: Kind) async {
        guard on else { return setSwitch(false, kind) }
        if status(kind) != .fullAccess {
            asking.insert(kind)
            let store = store()
            _ = try? await (kind == .events ? store.requestFullAccessToEvents() : store.requestFullAccessToReminders())
            asking.remove(kind)
            readStatuses()
        }
        setSwitch(status(kind) == .fullAccess, kind)
    }

    func isHidden(_ id: String, _ kind: Kind) -> Bool {
        (kind == .events ? hiddenCalendars : hiddenLists).contains(id)
    }

    /// Ticks or unticks a calendar or list.
    func setHidden(_ hidden: Bool, _ id: String, _ kind: Kind) {
        switch kind {
        case .events: if hidden { hiddenCalendars.insert(id) } else { hiddenCalendars.remove(id) }
        case .reminders: if hidden { hiddenLists.insert(id) } else { hiddenLists.remove(id) }
        }
        fetch()
    }

    /// Fetches for Today and for Upcoming through `last`, when either has changed.
    func update(today: LocalDate, through last: LocalDate) {
        if let window, window.today == today, window.last == last { return }
        window = (today, max(today, last))
        fetch()
    }

    /// Reads access again and fetches: when the app becomes active, and when the calendars change.
    func refresh() {
        readStatuses()
        fetch()
    }

    // MARK: Fetching

    private func status(_ kind: Kind) -> EKAuthorizationStatus {
        kind == .events ? eventStatus : reminderStatus
    }

    private func setSwitch(_ on: Bool, _ kind: Kind) {
        switch kind {
        case .events: showsEvents = on
        case .reminders: showsReminders = on
        }
        fetch()
    }

    private func readStatuses() {
        let events = EKEventStore.authorizationStatus(for: .event), reminders = EKEventStore.authorizationStatus(for: .reminder)
        if events != eventStatus { eventStatus = events }
        if reminders != reminderStatus { reminderStatus = reminders }
    }

    /// The one event store, made on first use and watched for changes.
    private func store() -> EKEventStore {
        if let eventStore { return eventStore }
        let store = EKEventStore()
        eventStore = store
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetch() }
        }
        return store
    }

    private func fetch() {
        fetches += 1
        let fetch = fetches
        let showsEvents = isShown(.events), showsReminders = isShown(.reminders)
        let store: EKEventStore? = showsEvents || showsReminders ? store() : nil
        calendarSources = showsEvents ? store.map { Self.sources($0.calendars(for: .event)) } ?? [] : []
        listSources = showsReminders ? store.map { Self.sources($0.calendars(for: .reminder)) } ?? [] : []
        guard let window, let store else { return apply(events: [], reminders: [], window: window) }

        let calendar = Calendar.current
        let start = window.today.date(in: calendar), end = window.last.adding(days: 1).date(in: calendar)
        var events: [ExternalEvent] = []
        let calendars = store.calendars(for: .event).filter { !hiddenCalendars.contains($0.calendarIdentifier) }
        if showsEvents, !calendars.isEmpty {
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
            events = store.events(matching: predicate).map(Self.event)
        }
        let lists = store.calendars(for: .reminder).filter { !hiddenLists.contains($0.calendarIdentifier) }
        guard showsReminders, !lists.isEmpty else { return apply(events: events, reminders: [], window: window) }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: lists)
        Task {
            let reminders = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { continuation.resume(returning: ($0 ?? []).map(Self.reminder)) }
            }
            guard fetch == fetches else { return }
            apply(events: events, reminders: reminders, window: window)
        }
    }

    private func apply(events: [ExternalEvent], reminders: [ExternalReminder], window: (today: LocalDate, last: LocalDate)?) {
        let today = window?.today ?? LocalDate(Date())
        let todayEvents = DayEvent.on(today, from: events)
        let upcomingEvents = window.map { DayEvent.byDay(events, from: today.adding(days: 1), through: $0.last) } ?? [:]
        let todayReminders = ExternalReminder.today(reminders, today: today)
        let upcomingReminders = ExternalReminder.upcoming(reminders, after: today)
        // Assigning an equal list would still redraw Today and Upcoming.
        if todayEvents != self.todayEvents { self.todayEvents = todayEvents }
        if upcomingEvents != self.upcomingEvents { self.upcomingEvents = upcomingEvents }
        if todayReminders != self.todayReminders { self.todayReminders = todayReminders }
        if upcomingReminders != self.upcomingReminders { self.upcomingReminders = upcomingReminders }
    }

    // MARK: EventKit values

    private static func sources(_ calendars: [EKCalendar]) -> [Source] {
        Dictionary(grouping: calendars) { $0.source?.sourceIdentifier ?? "" }
            .map { id, calendars in
                Source(id: id, title: calendars.first?.source?.title ?? "Other",
                       calendars: calendars.map { ListChoice(id: $0.calendarIdentifier, title: $0.title, color: hex($0.cgColor)) }
                           .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private nonisolated static func event(_ event: EKEvent) -> ExternalEvent {
        ExternalEvent(identifier: event.eventIdentifier ?? event.calendarItemIdentifier, title: event.title ?? "",
                      start: event.startDate, end: event.endDate, isAllDay: event.isAllDay, color: hex(event.calendar?.cgColor))
    }

    private nonisolated static func reminder(_ reminder: EKReminder) -> ExternalReminder {
        let due = reminder.dueDateComponents.flatMap { components -> LocalDate? in
            guard components.hour != nil || components.timeZone != nil else {
                return components.year.flatMap { year in components.month.flatMap { month in
                    components.day.flatMap { LocalDate(year: year, month: month, day: $0) } } }
            }
            return Calendar.current.date(from: components).map { LocalDate($0) }
        }
        return ExternalReminder(identifier: reminder.calendarItemIdentifier, title: reminder.title ?? "", due: due,
                                color: hex(reminder.calendar?.cgColor))
    }

    /// `#RRGGBB` in sRGB; grey when the calendar has no colour.
    nonisolated static func hex(_ color: CGColor?) -> String {
        guard let color, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let parts = converted.components, parts.count >= 3 else { return "#8E8E93" }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(parts[0]), byte(parts[1]), byte(parts[2]))
    }
}
