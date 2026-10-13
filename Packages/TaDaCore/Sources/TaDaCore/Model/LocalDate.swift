import Foundation

/// A calendar day with no time or time zone, read from and written as `YYYY-MM-DD`.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns nil for days that don't exist, such as February 30.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...Self.daysIn(month: month, year: year)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses exactly `YYYY-MM-DD`. Times, other separators and impossible days are nil.
    public init?(_ string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for byte in bytes[range] {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}

extension LocalDate {
    /// The calendar day of `date` in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)!
    }

    public func adding(days: Int) -> LocalDate {
        let calendar = Self.utc
        let date = calendar.date(byAdding: .day, value: days, to: midnightUTC)!
        return LocalDate(date, calendar: calendar)
    }

    /// Whole days from `self` to `other`; negative when `other` is earlier.
    public func days(to other: LocalDate) -> Int {
        Self.utc.dateComponents([.day], from: midnightUTC, to: other.midnightUTC).day!
    }

    /// 1 = Sunday … 7 = Saturday, as in `Calendar`.
    public var weekday: Int {
        Self.utc.component(.weekday, from: midnightUTC)
    }

    /// The first day of this day's month.
    public var startOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1)! }

    /// The first day of the month `months` away.
    public func addingMonths(_ months: Int) -> LocalDate {
        let index = year * 12 + (month - 1) + months
        return LocalDate(year: index / 12, month: index % 12 + 1, day: 1)!
    }

    /// The same day `months` away, or that month's last day when it's shorter; nil outside years 1 to 9999.
    public func adding(months: Int) -> LocalDate? {
        let index = year * 12 + (month - 1) + months
        for last in stride(from: day, through: max(day - 3, 1), by: -1) {
            if let date = LocalDate(year: index / 12, month: index % 12 + 1, day: last) { return date }
        }
        return nil
    }

    /// The coming Saturday, or this day on a Saturday or Sunday.
    public var thisWeekend: LocalDate {
        weekday == 1 ? self : adding(days: 7 - weekday)
    }

    /// The first day of the week after this day's, from `firstWeekday` (1 = Sunday, as in `Calendar`).
    public func nextWeek(firstWeekday: Int) -> LocalDate {
        adding(days: 7 - (weekday - firstWeekday + 7) % 7)
    }

    /// The same day at midnight in `calendar`'s time zone, for formatting and date pickers.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // Day arithmetic in UTC, where every day is 24 hours long.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var midnightUTC: Date { date(in: Self.utc) }
}
