import Foundation

/// Which a numeric date such as 5/12 gives first: the day (5 December) or the month (May 12).
public enum DayOrder: Sendable {
    case dayMonth
    case monthDay
}

/// Reads a typed date such as "fri", "3d", "dec 25" or "25/12" as a day. A phrase without a year never gives a
/// day before today; a weekday is its soonest coming day, today included, with or without "next". Times
/// ("3pm", "at 15:00") are ignored. A word's start counts as the word, so a phrase matches while it's typed:
/// "t" is today, "tu" Tuesday, "n" next week.
public enum DatePhrase {
    public static func parse(_ text: String, today: LocalDate, order: DayOrder, calendar: Calendar = .current) -> LocalDate? {
        let words = words(in: text)
        guard !words.isEmpty else { return nil }
        let phrase = words.joined(separator: " ")
        return named(phrase, today: today, calendar: calendar)
            ?? relative(phrase, today: today)
            ?? dayNumber(phrase, today: today)
            ?? numeric(phrase, today: today, order: order)
            ?? dayAndMonthName(phrase, today: today)
    }

    /// The lowercased words, without commas, times, "at" and "the", and without separators after the last one.
    private static func words(in text: String) -> [String] {
        var words: [String] = []
        for word in text.lowercased().replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace) {
            let word = String(word)
            if word == "at" || word == "the" || isTime(word) { continue }
            if word == "am" || word == "pm", let last = words.last, last.wholeMatch(of: /[0-9]{1,2}/) != nil {
                words.removeLast()
                continue
            }
            words.append(word)
        }
        if let last = words.popLast() {
            let trimmed = String(last.reversed().drop(while: { "/.-".contains($0) }).reversed())
            if !trimmed.isEmpty { words.append(trimmed) }
        }
        return words
    }

    private static func isTime(_ word: String) -> Bool {
        word.wholeMatch(of: /[0-9]{1,2}(:[0-9]{2})?(am|pm|a|p)/) != nil || word.wholeMatch(of: /[0-9]{1,2}:[0-9]{2}/) != nil
    }

    // MARK: Words

    private enum Named {
        case today, tomorrow, weekday(Int), weekend, nextWeek, nextMonth, endOfMonth
    }

    /// Weekdays from Monday, with `Calendar`'s numbers (1 = Sunday).
    private static let weekdays: [(name: String, number: Int)] = [
        ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7), ("sunday", 1),
    ]

    private static let exact: [String: Named] = [
        "tod": .today, "tmr": .tomorrow, "tom": .tomorrow, "wknd": .weekend, "eom": .endOfMonth, "next wk": .nextWeek,
        "mon": .weekday(2), "tue": .weekday(3), "tues": .weekday(3), "wed": .weekday(4), "thu": .weekday(5),
        "thur": .weekday(5), "thurs": .weekday(5), "fri": .weekday(6), "sat": .weekday(7), "sun": .weekday(1),
    ]

    /// Whole phrases in the order a typed start picks them.
    private static let phrases: [(phrase: String, named: Named)] =
        [("today", .today), ("tomorrow", .tomorrow)]
        + weekdays.map { ($0.name, .weekday($0.number)) }
        + [("weekend", .weekend), ("next week", .nextWeek), ("next month", .nextMonth), ("end of month", .endOfMonth)]

    private static func named(_ phrase: String, today: LocalDate, calendar: Calendar) -> LocalDate? {
        named(phrase).map { date(of: $0, today: today, calendar: calendar) }
    }

    private static func named(_ phrase: String) -> Named? {
        if let named = exact[phrase] { return named }
        if let named = phrases.first(where: { $0.phrase == phrase })?.named { return named }
        // "on fri", "this weekend", "next tue": the lead word changes nothing.
        var rest: Substring?
        for lead in ["on ", "this ", "next "] where phrase.hasPrefix(lead) { rest = phrase.dropFirst(lead.count) }
        if let rest, let named = exact[String(rest)] ?? phrases.first(where: { $0.phrase == rest })?.named, isDay(named) {
            return named
        }
        if let named = phrases.first(where: { $0.phrase.hasPrefix(phrase) })?.named { return named }
        if let rest, !rest.isEmpty, let named = phrases.first(where: { isDay($0.named) && $0.phrase.hasPrefix(rest) })?.named {
            return named
        }
        return nil
    }

    private static func isDay(_ named: Named) -> Bool {
        switch named {
        case .weekday, .weekend: true
        default: false
        }
    }

    private static func date(of named: Named, today: LocalDate, calendar: Calendar) -> LocalDate {
        switch named {
        case .today: today
        case .tomorrow: today.adding(days: 1)
        case .weekday(let number): today.adding(days: (number - today.weekday + 7) % 7)
        case .weekend: today.thisWeekend
        case .nextWeek: today.nextWeek(calendar: calendar)
        case .nextMonth: today.addingMonths(1)
        case .endOfMonth: today.addingMonths(1).adding(days: -1)
        }
    }

    // MARK: Numbers

    /// "3d", "2w", "1m", "1y", "+3", "in 3 days": today plus that many days, weeks, months or years.
    private static func relative(_ phrase: String, today: LocalDate) -> LocalDate? {
        guard let match = phrase.wholeMatch(of: /(in )?(\+)?([0-9]{1,4}) ?([a-z]*)/), let count = Int(match.3) else { return nil }
        let unit = match.4
        if unit.isEmpty {
            return match.1 != nil || match.2 != nil ? today.adding(days: count) : nil
        }
        if "days".hasPrefix(unit) { return today.adding(days: count) }
        if "weeks".hasPrefix(unit) || unit == "wk" || unit == "wks" { return today.adding(days: count * 7) }
        if "months".hasPrefix(unit) || unit == "mos" { return adding(months: count, to: today) }
        if "years".hasPrefix(unit) || unit == "yr" || unit == "yrs" { return adding(months: count * 12, to: today) }
        return nil
    }

    /// The same day `months` away, or that month's last day when it's shorter; nil past year 9999.
    private static func adding(months: Int, to day: LocalDate) -> LocalDate? {
        let index = day.year * 12 + (day.month - 1) + months
        for last in stride(from: day.day, through: max(day.day - 3, 1), by: -1) {
            if let date = LocalDate(year: index / 12, month: index % 12 + 1, day: last) { return date }
        }
        return nil
    }

    /// "25", "25th": the soonest coming 25th.
    private static func dayNumber(_ phrase: String, today: LocalDate) -> LocalDate? {
        guard let match = phrase.wholeMatch(of: /([0-9]{1,2})(st|nd|rd|th)?/), let day = Int(match.1) else { return nil }
        for ahead in 0..<12 {
            let month = today.addingMonths(ahead)
            if let date = LocalDate(year: month.year, month: month.month, day: day), date >= today { return date }
        }
        return nil
    }

    /// "25/12", "25.12", "25-12", "25/12/27", "2027-12-25": by `order`, or year first with four digits.
    private static func numeric(_ phrase: String, today: LocalDate, order: DayOrder) -> LocalDate? {
        guard let match = phrase.wholeMatch(of: /([0-9]{1,4})[\/.\-]([0-9]{1,2})(?:[\/.\-]([0-9]{1,4}))?/),
              let first = Int(match.1), let second = Int(match.2) else { return nil }
        if match.1.count == 4 {
            guard let third = match.3, third.count <= 2, let day = Int(third) else { return nil }
            return LocalDate(year: first, month: second, day: day)
        }
        let (day, month) = order == .dayMonth ? (first, second) : (second, first)
        return date(day: day, month: month, year: match.3, today: today)
    }

    /// "25 dec", "dec 25", "25th of december 2027": a month's start that's no other month's start.
    private static func dayAndMonthName(_ phrase: String, today: LocalDate) -> LocalDate? {
        let dayFirst = /([0-9]{1,2})(?:st|nd|rd|th)? ?(?:of )?([a-z]+)\.?(?: ([0-9]{2}|[0-9]{4}))?/
        let monthFirst = /([a-z]+)\.? ?([0-9]{1,2})(?:st|nd|rd|th)?(?: ([0-9]{2}|[0-9]{4}))?/
        if let match = phrase.wholeMatch(of: dayFirst), let day = Int(match.1), let month = month(named: match.2) {
            return date(day: day, month: month, year: match.3, today: today)
        }
        if let match = phrase.wholeMatch(of: monthFirst), let day = Int(match.2), let month = month(named: match.1) {
            return date(day: day, month: month, year: match.3, today: today)
        }
        return nil
    }

    private static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september",
                                 "october", "november", "december"]

    private static func month(named name: Substring) -> Int? {
        if name == "sept" { return 9 }
        let matches = months.indices.filter { months[$0].hasPrefix(name) }
        return matches.count == 1 ? matches[0] + 1 : nil
    }

    /// The day in `year` (two digits are 20xx), or with no year the soonest coming one, today included.
    private static func date(day: Int, month: Int, year: Substring?, today: LocalDate) -> LocalDate? {
        if let year {
            guard year.count == 2 || year.count == 4, let number = Int(year) else { return nil }
            return LocalDate(year: year.count == 2 ? 2000 + number : number, month: month, day: day)
        }
        for year in today.year...today.year + 8 {
            if let date = LocalDate(year: year, month: month, day: day), date >= today { return date }
        }
        return nil
    }
}
