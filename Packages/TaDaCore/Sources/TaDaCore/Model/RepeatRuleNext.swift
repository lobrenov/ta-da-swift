import Foundation

extension RepeatRule {
    /// The dates a repeating task moves to.
    public struct Next: Hashable, Sendable {
        public var dueDate: LocalDate?
        public var deadline: LocalDate?
    }

    /// The task's next dates (see Next date and End in `docs/file-format.md`), or nil when `until` ends the series
    /// or the date is past year 9999. `rolloverDay` is the day the task moves forward. A `when done` rule without a
    /// `completedDate` counts from the task's date, else from the day before `rolloverDay`; its result is never moved
    /// up to `rolloverDay`.
    public func next(dueDate: LocalDate?, deadline: LocalDate?, completedDate: LocalDate?,
                     rolloverDay: LocalDate) -> Next? {
        let before = rolloverDay.adding(days: -1)
        let found: LocalDate?
        if whenDone {
            found = afterDone(completedDate ?? dueDate ?? deadline ?? before)
        } else {
            found = regular(after: dueDate ?? deadline ?? completedDate ?? before, from: rolloverDay)
        }
        guard let date = found, until.map({ date <= $0 }) ?? true else { return nil }
        guard let dueDate else { return deadline == nil ? Next(dueDate: date) : Next(deadline: date) }
        guard let deadline else { return Next(dueDate: date) }
        guard let moved = date.checkedAdding(days: dueDate.days(to: deadline)) else { return nil }
        return Next(dueDate: date, deadline: moved)
    }

    /// The first date a task with no dates would be due: the first day of a rule that names its days (weekdays, a day of
    /// the month, a date) on or after `today`, else `today`. Nil when `until` has passed.
    public func firstDate(from today: LocalDate) -> LocalDate? {
        let namesDay = switch frequency {
        case .weekday: true
        case .week: !weekdays.isEmpty
        case .month: monthDay != nil
        case .year: yearDate != nil
        case .day: false
        }
        let date = namesDay ? first(onOrAfter: today, anchor: today, interval: 1) : today
        return date.flatMap { date in until.map { date <= $0 } ?? true ? date : nil }
    }

    /// The dates of a regular rule after `anchor`, on or after `from` and through `through`, each counted from `anchor`
    /// rather than from the one before; stops at `until`.
    func dates(after anchor: LocalDate, from: LocalDate, through: LocalDate) -> [LocalDate] {
        var result: [LocalDate] = []
        var start = from
        while let date = regular(after: anchor, from: start), date <= through, until.map({ date <= $0 }) ?? true {
            result.append(date)
            guard let following = date.checkedAdding(days: 1) else { break }
            start = following
        }
        return result
    }

    private func regular(after anchor: LocalDate, from: LocalDate) -> LocalDate? {
        guard let day = anchor.checkedAdding(days: 1) else { return nil }
        return first(onOrAfter: max(day, from), anchor: anchor, interval: interval)
    }

    private func afterDone(_ done: LocalDate) -> LocalDate? {
        switch frequency {
        case .day:
            return done.checkedAdding(days: interval)
        case .weekday:
            return done.checkedAdding(days: 1).flatMap { first(onOrAfter: $0, anchor: done, interval: 1) }
        case .week:
            guard !weekdays.isEmpty else { return done.checkedAdding(days: 7 * interval) }
            return done.checkedAdding(days: 1).flatMap { first(onOrAfter: $0, anchor: done, interval: 1) }?
                .checkedAdding(days: 7 * (interval - 1))
        case .month:
            guard monthDay != nil else { return done.adding(months: interval) }
            return namedDayAfterDone(done)
        case .year:
            guard yearDate != nil else { return done.adding(months: 12 * interval) }
            return namedDayAfterDone(done)
        }
    }

    /// A month or year rule's next named day after `done`, then `interval - 1` further periods.
    private func namedDayAfterDone(_ done: LocalDate) -> LocalDate? {
        guard let from = done.checkedAdding(days: 1), let start = first(onOrAfter: from, anchor: done, interval: 1) else { return nil }
        guard interval > 1 else { return start }
        return start.checkedAdding(days: 1).flatMap { first(onOrAfter: $0, anchor: start, interval: interval - 1) }
    }

    /// The first date of the rule on or after `t`, in periods of `n` days, weeks, months or years counted from `anchor`.
    private func first(onOrAfter t: LocalDate, anchor: LocalDate, interval n: Int) -> LocalDate? {
        let periods: Int
        switch frequency {
        case .weekday: return (0...2).compactMap { t.checkedAdding(days: $0) }.first { (2...6).contains($0.weekday) }
        case .day: periods = anchor.days(to: t)
        case .week: periods = anchor.mondayOfWeek.days(to: t.mondayOfWeek) / 7
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
            return anchor.checkedAdding(days: k).map { [$0] } ?? []
        case .week:
            let monday = anchor.mondayOfWeek
            return (weekdays.isEmpty ? [anchor.weekday] : Array(weekdays))
                .compactMap { monday.checkedAdding(days: 7 * k + ($0 + 5) % 7) }.sorted()
        case .month:
            let index = Self.monthIndex(anchor) + k
            let (year, month) = (index / 12, index % 12 + 1)
            guard let firstOfMonth = LocalDate(year: year, month: month, day: 1) else { return [] }
            let length = LocalDate.daysIn(month: month, year: year)
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
            return LocalDate(year: year, month: month, day: min(day, LocalDate.daysIn(month: month, year: year))).map { [$0] } ?? []
        }
    }

    private static func monthIndex(_ date: LocalDate) -> Int { date.year * 12 + date.month - 1 }
}
