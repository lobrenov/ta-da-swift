// Display formats and month grids for calendar days, in the user's locale.
import Foundation
import TaDaCore

extension LocalDate {
    enum Style {
        /// "Sat 3 Oct"
        case weekdayDayMonth
        /// "Sat 3 Oct 2026"
        case weekdayDayMonthYear
        /// "Fri 2"
        case weekdayDay
        /// "Saturday 3 Oct"
        case wideWeekdayDayMonth
        /// "Saturday 3 October"
        case fullDate
        /// "3 Oct"
        case dayMonth
        /// "3 Oct 2026"
        case dayMonthYear
        /// "Saturday"
        case weekday
        /// "Sat"
        case shortWeekday
        /// "October 2026"
        case monthYear
        /// "October"
        case month
    }

    func formatted(_ style: Style) -> String {
        let date = date()
        return switch style {
        case .weekdayDayMonth: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .weekdayDayMonthYear: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        case .weekdayDay: date.formatted(.dateTime.weekday(.abbreviated).day())
        case .wideWeekdayDayMonth: date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        case .fullDate: date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .dayMonth: date.formatted(.dateTime.day().month(.abbreviated))
        case .dayMonthYear: date.formatted(.dateTime.day().month(.abbreviated).year())
        case .weekday: date.formatted(.dateTime.weekday(.wide))
        case .shortWeekday: date.formatted(.dateTime.weekday(.abbreviated))
        case .monthYear: date.formatted(.dateTime.month(.wide).year())
        case .month: date.formatted(.dateTime.month(.wide))
        }
    }

    /// A later month's heading in Upcoming: "Later in October" for the rest of this month, then "November", or
    /// "January 2027" in another year.
    func agendaMonthTitle(today: LocalDate) -> String {
        if self == today.startOfMonth { return "Later in \(formatted(.month))" }
        return year == today.year ? formatted(.month) : formatted(.monthYear)
    }
}

extension DayOrder {
    /// The order of the day and month in the system's short date format (Language & Region).
    static var system: DayOrder {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        let format = formatter.dateFormat ?? ""
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return .dayMonth }
        return day < month ? .dayMonth : .monthDay
    }
}

/// A month laid out in weeks from the locale's first weekday: the weekday initials, and the month's days with
/// nil for the days before the 1st.
struct MonthGrid {
    let weekdaySymbols: [String]
    let days: [LocalDate?]

    init(_ month: LocalDate, calendar: Calendar = .current) {
        let month = month.startOfMonth
        // Weekday symbols start on Sunday; rotate them to the locale's first weekday.
        let first = calendar.firstWeekday - 1
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        weekdaySymbols = Array(symbols[first...] + symbols[..<first])
        let leading = (month.weekday - calendar.firstWeekday + 7) % 7
        days = Array(repeating: nil, count: leading) + (0..<month.days(to: month.addingMonths(1))).map { month.adding(days: $0) }
    }

    var weeks: Int { (days.count + 6) / 7 }
}
