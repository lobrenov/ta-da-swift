/// Moves a completed repeating task forward (see Repeating tasks in `docs/file-format.md`).
public enum Recurrence {
    /// The dates a completed task moves to on `today`: nil unless it's a Done or Cancelled task whose `repeat` reads as
    /// a rule with a next date, and whose project (`projectClosed`: it resolves and is Done or Cancelled) hasn't ended the series.
    public static func next(for item: Item, today: LocalDate, projectClosed: Bool) -> RepeatRule.Next? {
        let p = item.properties
        guard p.kind == .task, p.status.isClosed, !projectClosed, let rule = p.repeatRule?.rule else { return nil }
        return rule.next(dueDate: p.dueDate, deadline: p.deadline, completedDate: p.completedDate, rolloverDay: today)
    }

    /// `text` with the task moved forward in one splice: `status: Not Started`, `completedDate` emptied, `dueDate` and
    /// `deadline` set to the next dates (a key is added when missing), and subtasks `[x]`, `[X]`, `[/]` and `[-]` reset to
    /// `[ ]`. Unchanged when the task doesn't move forward.
    public static func moveForward(_ text: String, path: String, today: LocalDate, projectClosed: Bool) -> String {
        guard let item = Item(parsing: text, path: path),
              let next = next(for: item, today: today, projectClosed: projectClosed) else { return text }
        var result = text
        for box in item.checkboxes where "xX/-".contains(box.marker) {
            result = ChecklistEditor.setMarker(" ", of: box, in: result) ?? result
        }
        result = Completion.setStatus(.notStarted, in: result, today: today)
        if let due = next.dueDate { result = FrontmatterEditor.set("dueDate", to: .date(due), in: result) }
        if let deadline = next.deadline { result = FrontmatterEditor.set("deadline", to: .date(deadline), in: result) }
        return result
    }
}
