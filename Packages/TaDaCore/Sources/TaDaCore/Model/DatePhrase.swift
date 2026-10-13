import Foundation

/// Which a numeric date such as 5/12 gives first: the day (5 December) or the month (May 12).
public enum DayOrder: Sendable {
    case dayMonth
    case monthDay
}

/// Reads a typed date such as "fri", "3d", "dec 25" or "25/12" as a day. A phrase without a year never gives a
/// day before today; a weekday is its soonest coming day, today included, with or without "next". Times
/// ("3pm", "at 15:00", "at 3", and "fri 3" and "15:" on the way) are ignored. A word's start counts as the word, so a phrase matches while it's typed:
/// "t" is today, "tu" Tuesday, "n" next week.
public enum DatePhrase {
    public static func parse(_ text: String, today: LocalDate, order: DayOrder, firstWeekday: Int) -> LocalDate? {
        let words = words(in: text)
        guard !words.isEmpty else { return nil }
        let phrase = words.joined(separator: " ")
        return named(phrase, today: today, firstWeekday: firstWeekday)
            ?? relative(phrase, today: today)
            ?? dayNumber(phrase, today: today)
            ?? numeric(phrase, today: today, order: order)
            ?? dayAndMonthName(phrase, today: today)
            ?? namedWithHour(words, today: today, firstWeekday: firstWeekday)
    }

    /// "fri 3", while "fri 3pm" is typed: a named day and an hour.
    private static func namedWithHour(_ words: [String], today: LocalDate, firstWeekday: Int) -> LocalDate? {
        guard words.count > 1, words.last!.wholeMatch(of: /[0-9]{1,2}/) != nil else { return nil }
        return named(words.dropLast().joined(separator: " "), today: today, firstWeekday: firstWeekday)
    }

    /// The lowercased words, without commas, times, "at" and the hour after it, and "the", and without separators
    /// after the last one.
    private static func words(in text: String) -> [String] {
        var words: [String] = []
        var afterAt = false
        for word in text.lowercased().replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace) {
            let word = String(word)
            defer { afterAt = word == "at" }
            if afterAt, word.wholeMatch(of: /[0-9]{1,2}/) != nil { continue }
            if word == "at" || word == "the" || isTime(word) { continue }
            // "fri 3 pm" drops the 3; "dec 3 pm" keeps it as the day.
            if word == "am" || word == "pm" {
                if let last = words.last, last.wholeMatch(of: /[0-9]{1,2}/) != nil,
                   words.count < 2 || month(named: Substring(words[words.count - 2])) == nil {
                    words.removeLast()
                }
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
        word.wholeMatch(of: /[0-9]{1,2}(:[0-9]{0,2})?(am|pm|a|p)/) != nil || word.wholeMatch(of: /[0-9]{1,2}:[0-9]{0,2}/) != nil
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

    private static func named(_ phrase: String, today: LocalDate, firstWeekday: Int) -> LocalDate? {
        named(phrase).map { date(of: $0, today: today, firstWeekday: firstWeekday) }
    }

    private static func named(_ phrase: String) -> Named? {
        if let named = exact[phrase] { return named }
        if let named = phrases.first(where: { $0.phrase == phrase })?.named { return named }
        // "on fri", "this weekend", "next tue": the lead word changes nothing.
        var rest: Substring?
        for lead in ["on ", "this ", "next "] where phrase.hasPrefix(lead) { rest = phrase.dropFirst(lead.count) }
        if let rest, let named = exact[String(rest)] ?? phrases.first(where: { $0.phrase == rest })?.named { return named }
        if let named = phrases.first(where: { $0.phrase.hasPrefix(phrase) })?.named { return named }
        if let rest, !rest.isEmpty { return phrases.first(where: { $0.phrase.hasPrefix(rest) })?.named }
        return nil
    }

    private static func date(of named: Named, today: LocalDate, firstWeekday: Int) -> LocalDate {
        switch named {
        case .today: today
        case .tomorrow: today.adding(days: 1)
        case .weekday(let number): today.adding(days: (number - today.weekday + 7) % 7)
        case .weekend: today.thisWeekend
        case .nextWeek: today.nextWeek(firstWeekday: firstWeekday)
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
        if "months".hasPrefix(unit) || unit == "mos" { return today.adding(months: count) }
        if "years".hasPrefix(unit) || unit == "yr" || unit == "yrs" { return today.adding(months: count * 12) }
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
        let matches = months.indices.filter { months[$0].hasPrefix(name) }
        return matches.count == 1 ? matches[0] + 1 : nil
    }

    /// The day in `year`, or with no year the soonest coming one, today included. Two digits are 20xx, and
    /// not before today, so typing a four-digit year doesn't pass through 20.
    private static func date(day: Int, month: Int, year: Substring?, today: LocalDate) -> LocalDate? {
        if let year {
            guard let number = Int(year) else { return nil }
            switch year.count {
            case 2: return LocalDate(year: 2000 + number, month: month, day: day).flatMap { $0 >= today ? $0 : nil }
            case 4: return LocalDate(year: number, month: month, day: day)
            default: return nil
            }
        }
        for year in today.year...today.year + 8 {
            if let date = LocalDate(year: year, month: month, day: day), date >= today { return date }
        }
        return nil
    }
}
