// The iPhone Agenda's paging: the scroll key of each page (a day or a week) and of each strip week, so swiping either
// moves the selection and the selection moves both.
import TaDaCore

enum AgendaPaging {
    /// A Monday: keys count days, or weeks, from it.
    private static let epoch = LocalDate(year: 2001, month: 1, day: 1)!
    /// How many days (or weeks) either side of today can be paged to.
    static let dayReach = 730
    static let weekReach = 105

    /// The page a selection is on: its day, or its week.
    static func key(of selection: AppModel.AgendaSelection) -> Int {
        switch selection {
        case let .day(day): epoch.days(to: day)
        case let .week(week): epoch.days(to: week.firstDay) / 7
        }
    }

    /// The selection of page `key`, of the same kind as `selection`.
    static func selection(forKey key: Int, like selection: AppModel.AgendaSelection) -> AppModel.AgendaSelection {
        switch selection {
        case .day: .day(epoch.adding(days: key))
        case .week: .week(epoch.adding(days: key * 7).isoWeek)
        }
    }

    /// The pages: a day's or a week's keys around today.
    static func keys(like selection: AppModel.AgendaSelection, today: LocalDate) -> ClosedRange<Int> {
        switch selection {
        case .day:
            let center = key(of: .day(today))
            return center - dayReach...center + dayReach
        case .week:
            let center = key(of: .week(today.isoWeek))
            return center - weekReach...center + weekReach
        }
    }

    /// The strip's key for the week a selection is in.
    static func weekKey(of selection: AppModel.AgendaSelection) -> Int {
        switch selection {
        case let .day(day): key(of: .week(day.isoWeek))
        case .week: key(of: selection)
        }
    }

    static func weeks(today: LocalDate) -> ClosedRange<Int> {
        keys(like: .week(today.isoWeek), today: today)
    }

    static func week(forKey key: Int) -> ISOWeek {
        epoch.adding(days: key * 7).isoWeek
    }

    /// What swiping the strip to week `key` selects: the selection moved by whole weeks, so a day keeps its weekday.
    static func selection(movingToWeek key: Int, from selection: AppModel.AgendaSelection) -> AppModel.AgendaSelection {
        let weeks = key - weekKey(of: selection)
        switch selection {
        case let .day(day): return .day(day.adding(days: weeks * 7))
        case let .week(week): return .week(week.adding(weeks: weeks))
        }
    }
}
