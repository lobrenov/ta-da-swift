/// Where a repeating task goes when logging moves it forward.
public enum RepeatMove: Hashable, Sendable {
    /// The task reopens on this date (its due date, else its deadline).
    case moves(to: LocalDate)
    /// The series ends: `until` or the task's project ends it, so the task logs.
    case ends
}

extension VaultIndex {
    /// The day logging moves a task completed on `completedDate` forward on: `today`, or the day after for a task
    /// completed today.
    static func rolloverDay(completedDate: LocalDate?, today: LocalDate) -> LocalDate {
        (completedDate.map { $0 < today } ?? true) ? today : today.adding(days: 1)
    }

    /// What logging does to a repeating task: nil unless it's a task whose rule reads and that is Done or Cancelled.
    /// With `completing`, an open task counts as completed today, so this is where it would move. Uses the same
    /// decision as the logging run, including a closed project ending the series.
    public func repeatMove(of item: Item, today: LocalDate, completing: Bool = false) -> RepeatMove? {
        var item = item
        guard item.properties.kind == .task, item.properties.repeatRule?.rule != nil else { return nil }
        if completing, !item.properties.status.isClosed {
            item.properties.status = .done
            item.properties.completedDate = today
        }
        guard item.properties.status.isClosed else { return nil }
        let rollover = Self.rolloverDay(completedDate: item.properties.completedDate, today: today)
        let closed = project(of: item)?.properties.status.isClosed == true
        guard let next = Recurrence.next(for: item, today: rollover, projectClosed: closed),
              let date = next.dueDate ?? next.deadline else { return .ends }
        return .moves(to: date)
    }
}
