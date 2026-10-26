import Foundation

/// A task's `repeat` value: its text as written, and the rule when the text reads as one.
public struct Repeat: Hashable, Sendable {
    public var text: String
    public var rule: RepeatRule?

    public init(text: String, rule: RepeatRule?) {
        self.text = text
        self.rule = rule
    }
}

/// A repeating task's schedule, read from and written as an English phrase (see Repeating tasks in
/// `docs/file-format.md`). Weekdays are `Calendar` numbers, 1 = Sunday … 7 = Saturday.
public struct RepeatRule: Hashable, Sendable {
    public enum Frequency: Sendable { case day, weekday, week, month, year }

    /// The day a month rule falls on.
    public enum MonthDay: Hashable, Sendable {
        case day(Int)
        case lastDay
        /// The nth (1…5) weekday of the month.
        case nth(Int, weekday: Int)
        case lastWeekday(Int)
    }

    public struct YearDate: Hashable, Sendable {
        public var month: Int
        public var day: Int
    }

    public private(set) var frequency: Frequency
    /// 1…999; always 1 for `weekday`.
    public private(set) var interval = 1
    /// Week rules; empty takes the weekday from `dueDate`.
    public private(set) var weekdays: Set<Int> = []
    /// Month rules; nil takes the day from `dueDate`.
    public private(set) var monthDay: MonthDay?
    /// Year rules; nil takes the date from `dueDate`.
    public private(set) var yearDate: YearDate?
    public private(set) var until: LocalDate?
    public private(set) var whenDone = false

    /// Nil when a value is out of range. Fields that don't belong to the frequency are dropped.
    public init?(frequency: Frequency, interval: Int = 1, weekdays: Set<Int> = [], monthDay: MonthDay? = nil,
                 yearDate: YearDate? = nil, until: LocalDate? = nil, whenDone: Bool = false) {
        guard (1...999).contains(interval), frequency != .weekday || interval == 1,
              weekdays.allSatisfy((1...7).contains) else { return nil }
        switch monthDay {
        case let .day(day): guard (1...31).contains(day) else { return nil }
        case let .nth(n, weekday): guard (1...5).contains(n), (1...7).contains(weekday) else { return nil }
        case let .lastWeekday(weekday): guard (1...7).contains(weekday) else { return nil }
        case .lastDay, nil: break
        }
        if let yearDate {
            guard (1...12).contains(yearDate.month),
                  (1...Self.monthLengths[yearDate.month - 1]).contains(yearDate.day) else { return nil }
        }
        self.frequency = frequency
        self.interval = interval
        self.weekdays = frequency == .week ? weekdays : []
        self.monthDay = frequency == .month ? monthDay : nil
        self.yearDate = frequency == .year ? yearDate : nil
        self.until = until
        self.whenDone = whenDone
    }
}

extension RepeatRule {
    private static let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    private static let fullDayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let fullMonthNames = ["january", "february", "march", "april", "may", "june", "july", "august",
                                         "september", "october", "november", "december"]
    private static let monthLengths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    /// Reads a phrase; nil when it isn't a rule.
    public static func parse(_ text: String) -> RepeatRule? {
        var tokens = text.lowercased().replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace).map(String.init)[...]
        guard tokens.popFirst() == "every", var unit = tokens.popFirst() else { return nil }
        var interval = 1
        if let number = Int(unit) {
            guard let next = tokens.popFirst() else { return nil }
            interval = number
            unit = next
        }
        var weekdays: Set<Int> = []
        let frequency: Frequency
        switch unit {
        case "day", "days": frequency = .day
        case "weekday": frequency = .weekday
        case "week", "weeks": frequency = .week
        case "month", "months": frequency = .month
        case "year", "years": frequency = .year
        default:
            // `every mon, thu` is `every week on mon, thu`.
            guard interval == 1, let first = weekday(unit) else { return nil }
            frequency = .week
            weekdays.insert(first)
            while let token = tokens.first, token != "until", token != "when" {
                guard let day = weekday(token) else { return nil }
                weekdays.insert(day)
                tokens.removeFirst()
            }
        }
        var monthDay: MonthDay?
        var yearDate: YearDate?
        var until: LocalDate?
        var whenDone = false

        if tokens.first == "on" {
            tokens.removeFirst()
            var clause: [String] = []
            while let token = tokens.first, token != "until", token != "when" {
                clause.append(token)
                tokens.removeFirst()
            }
            switch frequency {
            case .week:
                guard !clause.isEmpty else { return nil }
                for name in clause {
                    guard let weekday = weekday(name) else { return nil }
                    weekdays.insert(weekday)
                }
            case .month:
                guard let parsed = Self.monthDay(clause) else { return nil }
                monthDay = parsed
            case .year:
                guard let parsed = Self.yearDate(clause) else { return nil }
                yearDate = parsed
            case .day, .weekday:
                return nil
            }
        }

        var sawUntil = false, sawWhenDone = false
        while let token = tokens.popFirst() {
            switch token {
            case "until" where !sawUntil:
                guard let date = tokens.popFirst().flatMap(LocalDate.init) else { return nil }
                until = date
                sawUntil = true
            case "when" where !sawWhenDone:
                guard tokens.popFirst() == "done" else { return nil }
                whenDone = true
                sawWhenDone = true
            default:
                return nil
            }
        }
        return RepeatRule(frequency: frequency, interval: interval, weekdays: weekdays, monthDay: monthDay,
                          yearDate: yearDate, until: until, whenDone: whenDone)
    }

    /// The canonical form: `until` before `when done`, three-letter days and months, `1st`…`5th`.
    /// A month or year rule without a day writes without one; Ta Da writes them with the day from `dueDate`.
    public var phrase: String {
        words(every: "every", dayName: Self.dayName, monthName: Self.monthName, list: { $0.joined(separator: ", ") },
              until: { $0.description })
    }

    /// The rule with a month or year rule's day taken from `date` when it names none, as Ta Da writes it.
    public func anchored(to date: LocalDate) -> RepeatRule {
        var rule = self
        if frequency == .month, monthDay == nil { rule.monthDay = .day(date.day) }
        if frequency == .year, yearDate == nil { rule.yearDate = YearDate(month: date.month, day: date.day) }
        return rule
    }

    /// The rule ending on `until`, or never when it's nil.
    public func ending(on until: LocalDate?) -> RepeatRule {
        var rule = self
        rule.until = until
        return rule
    }

    /// The rule counting from completion, or on its schedule.
    public func whenDone(_ whenDone: Bool) -> RepeatRule {
        var rule = self
        rule.whenDone = whenDone
        return rule
    }

    /// The rule spelled out, with `format` writing the end date: "Every week on Monday",
    /// "Every month on the 2nd Tuesday until 2026-12-31 when done".
    public func description(until format: (LocalDate) -> String = { $0.description }) -> String {
        words(every: "Every", dayName: { Self.fullDayNames[$0 - 1].capitalized },
              monthName: { Self.fullMonthNames[$0 - 1].capitalized },
              list: { $0.count == 1 ? $0[0] : $0.dropLast().joined(separator: ", ") + " and " + $0[$0.count - 1] },
              until: format)
    }

    /// A short label for a chip: "Weekly", "Every 2 weeks when done".
    public var frequencyLabel: String {
        let label: String
        switch (frequency, interval) {
        case (.weekday, _): label = "Weekdays"
        case (.day, 1): label = "Daily"
        case (.week, 1): label = "Weekly"
        case (.month, 1): label = "Monthly"
        case (.year, 1): label = "Yearly"
        case (.day, _): label = "Every \(interval) days"
        case (.week, _): label = "Every \(interval) weeks"
        case (.month, _): label = "Every \(interval) months"
        case (.year, _): label = "Every \(interval) years"
        }
        return whenDone ? label + " when done" : label
    }

    /// The rule spelled out, its names, day list and end date written as given.
    private func words(every: String, dayName: (Int) -> String, monthName: (Int) -> String,
                       list: ([String]) -> String, until format: (LocalDate) -> String) -> String {
        var words: String
        switch frequency {
        case .weekday: words = "\(every) weekday"
        case .day: words = interval == 1 ? "\(every) day" : "\(every) \(interval) days"
        case .week: words = interval == 1 ? "\(every) week" : "\(every) \(interval) weeks"
        case .month: words = interval == 1 ? "\(every) month" : "\(every) \(interval) months"
        case .year: words = interval == 1 ? "\(every) year" : "\(every) \(interval) years"
        }
        switch frequency {
        case .week where !weekdays.isEmpty:
            words += " on " + list(((2...7).map { $0 } + [1]).filter(weekdays.contains).map(dayName))
        case .month:
            switch monthDay {
            case let .day(day): words += " on the \(Self.ordinal(day))"
            case .lastDay: words += " on the last day"
            case let .nth(n, weekday): words += " on the \(Self.ordinal(n)) \(dayName(weekday))"
            case let .lastWeekday(weekday): words += " on the last \(dayName(weekday))"
            case nil: break
            }
        case .year:
            if let yearDate { words += " on \(monthName(yearDate.month)) \(yearDate.day)" }
        default:
            break
        }
        if let until { words += " until \(format(until))" }
        if whenDone { words += " when done" }
        return words
    }

    private static func weekday(_ name: String) -> Int? {
        (dayNames.firstIndex(of: name) ?? fullDayNames.firstIndex(of: name)).map { $0 + 1 }
    }

    /// `the 15th`, `the last day`, `the 2nd tuesday`, `the last friday`.
    private static func monthDay(_ clause: [String]) -> MonthDay? {
        guard clause.first == "the" else { return nil }
        let rest = Array(clause.dropFirst())
        switch rest.count {
        case 1:
            guard let day = number(rest[0]), (1...31).contains(day) else { return nil }
            return .day(day)
        case 2 where rest[0] == "last":
            if rest[1] == "day" { return .lastDay }
            return weekday(rest[1]).map(MonthDay.lastWeekday)
        case 2:
            guard let n = number(rest[0]), (1...5).contains(n), let weekday = weekday(rest[1]) else { return nil }
            return .nth(n, weekday: weekday)
        default:
            return nil
        }
    }

    /// `oct 26`.
    private static func yearDate(_ clause: [String]) -> YearDate? {
        guard clause.count == 2,
              let index = monthNames.firstIndex(of: clause[0]) ?? fullMonthNames.firstIndex(of: clause[0]),
              let day = number(clause[1]), (1...monthLengths[index]).contains(day) else { return nil }
        return YearDate(month: index + 1, day: day)
    }

    /// `15` or `15th`.
    private static func number(_ token: String) -> Int? {
        let digits = token.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, ["", "st", "nd", "rd", "th"].contains(token.dropFirst(digits.count)) else { return nil }
        return Int(digits)
    }

    private static func dayName(_ weekday: Int) -> String { dayNames[weekday - 1].capitalized }

    private static func monthName(_ month: Int) -> String { monthNames[month - 1].capitalized }

    private static func ordinal(_ n: Int) -> String {
        switch n {
        case 11...13: "\(n)th"
        default: "\(n)" + ["th", "st", "nd", "rd"][n % 10 < 4 ? n % 10 : 0]
        }
    }
}
