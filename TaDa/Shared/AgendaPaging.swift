// The Agenda's paging: the scroll key of each iPhone page (a day or a week) and of each strip week or month, so swiping
// either moves the selection and the selection moves both.
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

    /// The strip's month pages: keys count months from the epoch, and each page is the month of a selection's anchor.
    static let monthReach = 24

    static func monthKey(of selection: AppModel.AgendaSelection) -> Int {
        let anchor = selection.anchor
        return (anchor.year - epoch.year) * 12 + anchor.month - 1
    }

    static func monthStart(forKey key: Int) -> LocalDate {
        LocalDate(year: epoch.year + key / 12, month: key % 12 + 1, day: 1)!
    }

    static func months(today: LocalDate) -> ClosedRange<Int> {
        let center = monthKey(of: .day(today))
        return center - monthReach...center + monthReach
    }

    /// The date whose month the Mac strip's title names: the shown month, or with the week showing, the month of the
    /// shown week's Monday.
    static func titleDate(of selection: AppModel.AgendaSelection, monthOpen: Bool) -> LocalDate {
        monthOpen ? selection.anchor : week(forKey: weekKey(of: selection)).firstDay
    }

    /// What scrolling the strip to month `key` selects: the selection moved by whole months.
    static func selection(movingToMonth key: Int, from selection: AppModel.AgendaSelection) -> AppModel.AgendaSelection {
        self.selection(stepping: key - monthKey(of: selection), byMonth: true, from: selection)
    }

    /// What stepping the Mac strip `steps` periods selects: a week or, with the month open, a month. A day keeps its
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

/// What a vertical trackpad swipe on the Mac strip does.
enum AgendaSwipe: Equatable {
    case openMonth, closeMonth

    /// Points of scrolling a swipe needs.
    static let threshold = 40.0

    /// The swipe `dx` and `dy` add up to, which moves content: down opens the month, up closes it.
    static func decide(dx: Double, dy: Double, monthOpen: Bool) -> AgendaSwipe? {
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

    /// The settle spring's starting speed, matched to the finger's: SwiftUI's `initialVelocity` is the share of the
    /// distance left covered per second.
    static func settleVelocity(from progress: CGFloat, open: Bool, velocity: CGFloat, range: CGFloat) -> CGFloat {
        let distance = (open ? 1 : 0) - progress
        guard range > 0, abs(distance) > 0.001 else { return 0 }
        return velocity / range / distance
    }
}
