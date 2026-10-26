import Foundation

extension RepeatRule {
    /// The dates a repeating task moves to.
    public struct Next: Hashable, Sendable {
        public var dueDate: LocalDate?
        public var deadline: LocalDate?
    }

    /// The task's next dates (see Next date and End in `docs/file-format.md`), or nil when `until` ends the series.
    /// `rolloverDay` is the day the task moves forward. A `when done` rule without a `completedDate` counts from
    /// the task's date, else from `rolloverDay`; its result is never moved up to `rolloverDay`.
    public func next(dueDate: LocalDate?, deadline: LocalDate?, completedDate: LocalDate?,
                     rolloverDay: LocalDate) -> Next? {
        let anchor = dueDate ?? deadline ?? completedDate ?? rolloverDay.adding(days: -1)
        let found: LocalDate?
        if whenDone {
            found = afterDone(completedDate ?? dueDate ?? deadline ?? rolloverDay)
        } else {
            found = first(onOrAfter: max(anchor.adding(days: 1), rolloverDay), anchor: anchor, interval: interval)
        }
        guard let date = found, until.map({ date <= $0 }) ?? true else { return nil }
        guard let dueDate else { return deadline == nil ? Next(dueDate: date) : Next(deadline: date) }
        return Next(dueDate: date, deadline: deadline.map { date.adding(days: dueDate.days(to: $0)) })
    }

    private func afterDone(_ done: LocalDate) -> LocalDate? {
        let from = done.adding(days: 1)
        switch frequency {
        case .day:
            return done.adding(days: interval)
        case .weekday:
            return first(onOrAfter: from, anchor: done, interval: 1)
        case .week:
            guard !weekdays.isEmpty else { return done.adding(days: 7 * interval) }
            return first(onOrAfter: from, anchor: done, interval: 1)?.adding(days: 7 * (interval - 1))
        case .month, .year:
            guard frequency == .month ? monthDay != nil : yearDate != nil else {
                return done.adding(months: (frequency == .month ? 1 : 12) * interval)
            }
            guard let start = first(onOrAfter: from, anchor: done, interval: 1) else { return nil }
            return interval == 1 ? start : first(onOrAfter: start.adding(days: 1), anchor: start, interval: interval - 1)
        }
    }

    /// The first date of the rule on or after `t`, in periods of `n` days, weeks, months or years counted from `anchor`.
    private func first(onOrAfter t: LocalDate, anchor: LocalDate, interval n: Int) -> LocalDate? {
        let periods: Int
        switch frequency {
        case .weekday: return (0...2).map { t.adding(days: $0) }.first { (2...6).contains($0.weekday) }
        case .day: periods = anchor.days(to: t)
        case .week: periods = Self.monday(anchor).days(to: Self.monday(t)) / 7
        case .month: periods = Self.monthIndex(t) - Self.monthIndex(anchor)
        case .year: periods = t.year - anchor.year
        }
        let start = max(0, periods / n)
        // A rule such as the 5th Monday skips months; 500 periods reach any month that has one.
        for k in start..<(start + 500) {
            if let date = dates(period: k * n, anchor: anchor).first(where: { $0 >= t }) { return date }
        }
        return nil
    }

    /// The rule's dates in the period `k` days, weeks, months or years after `anchor`'s, in order.
    private func dates(period k: Int, anchor: LocalDate) -> [LocalDate] {
        switch frequency {
        case .weekday:
            return []
        case .day:
            return [anchor.adding(days: k)]
        case .week:
            let monday = Self.monday(anchor).adding(days: 7 * k)
            return (weekdays.isEmpty ? [anchor.weekday] : Array(weekdays)).map { monday.adding(days: ($0 + 5) % 7) }.sorted()
        case .month:
            let index = Self.monthIndex(anchor) + k
            let (year, month) = (index / 12, index % 12 + 1)
            guard let firstOfMonth = LocalDate(year: year, month: month, day: 1) else { return [] }
            let length = Self.daysIn(month: month, year: year)
            let lastWeekday = (firstOfMonth.weekday + length - 2) % 7 + 1
            let day: Int
            switch monthDay ?? .day(anchor.day) {
            case let .day(wanted): day = min(wanted, length)
            case .lastDay: day = length
            case let .nth(n, weekday): day = 1 + (weekday - firstOfMonth.weekday + 7) % 7 + 7 * (n - 1)
            case let .lastWeekday(weekday): day = length - (lastWeekday - weekday + 7) % 7
            }
            return LocalDate(year: year, month: month, day: day).map { [$0] } ?? []
        case .year:
            let year = anchor.year + k
            let (month, day) = yearDate.map { ($0.month, $0.day) } ?? (anchor.month, anchor.day)
            return LocalDate(year: year, month: month, day: min(day, Self.daysIn(month: month, year: year))).map { [$0] } ?? []
        }
    }

    private static func monday(_ date: LocalDate) -> LocalDate { date.adding(days: -((date.weekday + 5) % 7)) }

    private static func monthIndex(_ date: LocalDate) -> Int { date.year * 12 + date.month - 1 }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}
