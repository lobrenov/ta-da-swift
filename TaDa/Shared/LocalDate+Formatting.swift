// Display formats and month grids for calendar days, in the user's locale.
import Foundation
import TaDaCore

extension LocalDate {
    enum Style {
        /// "Sat 3 Oct"
        case weekdayDayMonth
        /// "Sat 3 Oct 2026"
        case weekdayDayMonthYear
        /// "Saturday"
        case weekday
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
        case .weekday: date.formatted(.dateTime.weekday(.wide))
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

    /// The first day of this day's month.
    var startOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1)! }

    /// The first day of the month `months` away.
    func addingMonths(_ months: Int) -> LocalDate {
        let index = year * 12 + (month - 1) + months
        return LocalDate(year: index / 12, month: index % 12 + 1, day: 1)!
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
