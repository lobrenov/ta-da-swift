import Foundation

/// A Calendar event occurrence, read from the device's calendars. Ta Da never writes it.
public struct ExternalEvent: Hashable, Sendable, Identifiable {
    public var identifier: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// The calendar's colour as `#RRGGBB`.
    public var color: String

    public init(identifier: String, title: String, start: Date, end: Date, isAllDay: Bool, color: String) {
        self.identifier = identifier
        self.title = title
        self.start = start
        self.end = max(start, end)
        self.isAllDay = isAllDay
        self.color = color
    }

    /// A recurring event's occurrences share an identifier, so each is told apart by its start.
    public var id: String { "\(identifier)@\(start.timeIntervalSinceReferenceDate)" }

    public func hasEnded(now: Date) -> Bool { end <= now }

    /// The days the event covers in `calendar`'s time zone. An event ending exactly at midnight doesn't cover the day
    /// that midnight starts.
    public func days(in calendar: Calendar = .current) -> ClosedRange<LocalDate> {
        let first = LocalDate(start, calendar: calendar)
        var last = LocalDate(end, calendar: calendar)
        if end > start, endsAtMidnight(in: calendar) { last = last.adding(days: -1) }
        return first...max(first, last)
    }

    /// The event's row on `day`, or nil when it doesn't cover it. A timed event shows its start on its first day,
    /// All day on the days in between and "until" its end on its last; one ending at midnight is all day on its last.
    public func placement(on day: LocalDate, calendar: Calendar = .current) -> EventPlacement? {
        let days = days(in: calendar)
        guard days.contains(day) else { return nil }
        let count = days.lowerBound.days(to: days.upperBound) + 1
        let index = days.lowerBound.days(to: day) + 1
        if isAllDay { return .allDay(day: index, of: count) }
        if index == 1 { return .time(start) }
        if index == count, !endsAtMidnight(in: calendar) { return .until(end) }
        return .allDay(day: index, of: count)
    }

    private func endsAtMidnight(in calendar: Calendar) -> Bool {
        calendar.startOfDay(for: end) == end
    }
}

/// Where an event sits on one day.
public enum EventPlacement: Hashable, Sendable {
    /// The first day of a timed event, at its start.
    case time(Date)
    /// An all-day event's day `day` of `of`, or a day inside a timed event.
    case allDay(day: Int, of: Int)
    /// The last day of a timed event that started on an earlier day, until its end.
    case until(Date)

    public var isAllDay: Bool {
        if case .allDay = self { true } else { false }
    }
}

/// An event on one day.
public struct DayEvent: Hashable, Sendable, Identifiable {
    public var event: ExternalEvent
    public var placement: EventPlacement

    public init(event: ExternalEvent, placement: EventPlacement) {
        self.event = event
        self.placement = placement
    }

    public var id: String { event.id }

    /// "Day n of m" for an all-day event spanning days.
    public var dayOfSpan: (day: Int, of: Int)? {
        guard event.isAllDay, case let .allDay(day, of) = placement, of > 1 else { return nil }
        return (day, of)
    }

    /// The events covering `day`, all-day ones first, then by start, then title.
    public static func on(_ day: LocalDate, from events: [ExternalEvent], calendar: Calendar = .current) -> [DayEvent] {
        events.compactMap { event in event.placement(on: day, calendar: calendar).map { DayEvent(event: event, placement: $0) } }
            .sorted(by: byDayOrder)
    }

    /// The events covering each day from `first` through `last`, keyed by day, each day sorted as `on(_:from:)`.
    /// Days without events are left out.
    public static func byDay(_ events: [ExternalEvent], from first: LocalDate, through last: LocalDate,
                             calendar: Calendar = .current) -> [LocalDate: [DayEvent]] {
        var result: [LocalDate: [DayEvent]] = [:]
        for event in events {
            let days = event.days(in: calendar)
            var day = max(days.lowerBound, first)
            let end = min(days.upperBound, last)
            while day <= end {
                if let placement = event.placement(on: day, calendar: calendar) {
                    result[day, default: []].append(DayEvent(event: event, placement: placement))
                }
                day = day.adding(days: 1)
            }
        }
        return result.mapValues { $0.sorted(by: byDayOrder) }
    }

    private static func byDayOrder(_ a: DayEvent, _ b: DayEvent) -> Bool {
        if a.placement.isAllDay != b.placement.isAllDay { return a.placement.isAllDay }
        if a.event.start != b.event.start { return a.event.start < b.event.start }
        let order = a.event.title.localizedStandardCompare(b.event.title)
        return order == .orderedSame ? a.id < b.id : order == .orderedAscending
    }
}
