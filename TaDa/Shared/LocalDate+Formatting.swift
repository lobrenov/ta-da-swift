// Display formats for calendar days, in the user's locale.
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

    /// The first day of this day's month.
    var startOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1)! }

    /// The first day of the month `months` away.
    func addingMonths(_ months: Int) -> LocalDate {
        let index = year * 12 + (month - 1) + months
        return LocalDate(year: index / 12, month: index % 12 + 1, day: 1)!
    }
}
