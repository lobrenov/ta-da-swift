// The iPhone Agenda's paging: the scroll key of each page (a day or a week) and of each strip week, so swiping either
// moves the selection and the selection moves both.
import CoreGraphics
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

    /// What swiping the Mac strip `steps` periods selects: a week or, with the month open, a month. A day keeps its
    /// weekday or its day of the month (the last day of a shorter month); a week moves to the one holding its
    /// Thursday, moved by the same months.
    static func selection(stepping steps: Int, byMonth: Bool, from selection: AppModel.AgendaSelection) -> AppModel.AgendaSelection {
        switch selection {
        case let .day(day): .day(byMonth ? day.adding(months: steps) ?? day : day.adding(days: steps * 7))
        case let .week(week):
            .week(byMonth ? (week.firstDay.adding(days: 3).adding(months: steps) ?? week.firstDay).isoWeek : week.adding(weeks: steps))
        }
    }
}

/// What a trackpad swipe on the Mac strip does.
enum AgendaSwipe: Equatable {
    /// Next (+1) or previous (-1) period.
    case step(Int)
    case openMonth, closeMonth

    /// Points of scrolling a swipe needs.
    static let threshold = 40.0

    /// The swipe `dx` and `dy` add up to, which moves content: left is next, down opens the month, up closes it.
    static func decide(dx: Double, dy: Double, monthOpen: Bool) -> AgendaSwipe? {
        if abs(dx) >= threshold, abs(dx) > abs(dy) { return .step(dx < 0 ? 1 : -1) }
        guard abs(dy) >= threshold, abs(dy) > abs(dx), (dy > 0) != monthOpen else { return nil }
        return monthOpen ? .closeMonth : .openMonth
    }
}

/// One swipe's scrolling, firing once.
struct AgendaSwipeTracker {
    private var dx = 0.0, dy = 0.0, fired = false

    mutating func reset() { self = AgendaSwipeTracker() }

    mutating func add(dx: Double, dy: Double, monthOpen: Bool) -> AgendaSwipe? {
        guard !fired else { return nil }
        self.dx += dx
        self.dy += dy
        let swipe = AgendaSwipe.decide(dx: self.dx, dy: self.dy, monthOpen: monthOpen)
        fired = swipe != nil
        return swipe
    }
}

/// Dragging the iPhone strip between one week and the month: `progress` runs from 0 (a week) to 1 (the month).
enum AgendaMonthDrag {
    static let rowSpacing: CGFloat = 2
    /// How far the finger travels, in seconds of velocity, past where it lifts.
    private static let projection: CGFloat = 0.15

    /// How much taller the month is than a week.
    static func range(weeks: Int, rowHeight: CGFloat) -> CGFloat {
        CGFloat(max(weeks - 1, 0)) * (rowHeight + rowSpacing)
    }

    /// A mostly-vertical drag belongs to the month; a mostly-horizontal one pages.
    static func isVertical(dx: CGFloat, dy: CGFloat) -> Bool { abs(dy) > abs(dx) }

    /// The progress after the finger moves `translation` (down is positive) from `start`.
    static func progress(start: CGFloat, translation: CGFloat, range: CGFloat) -> CGFloat {
        range > 0 ? min(1, max(0, start + translation / range)) : start
    }

    /// Whether a drag lifted at `progress` with `velocity` (points per second, down is positive) settles open.
    static func settlesOpen(progress: CGFloat, velocity: CGFloat, range: CGFloat) -> Bool {
        range > 0 && progress + velocity * projection / range > 0.5
    }
}
