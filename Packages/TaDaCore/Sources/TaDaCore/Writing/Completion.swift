/// Keeps `completedDate` in step with `status`, which is the source of truth.
public enum Completion {
    /// Done and Cancelled also set `completedDate: today`; any other status clears `completedDate`.
    public static func setStatus(_ status: Status, in text: String, today: LocalDate) -> String {
        let withStatus = FrontmatterEditor.set("status", to: .text(status.rawValue), in: text)
        return status.isClosed
            ? FrontmatterEditor.set("completedDate", to: .date(today), in: withStatus)
            : FrontmatterEditor.clear("completedDate", in: withStatus)
    }

    /// Done or Cancelled → Not Started, anything else → Done: what a row or editor checkbox does.
    public static func toggle(_ current: Status, in text: String, today: LocalDate) -> String {
        setStatus(current.isClosed ? .notStarted : .done, in: text, today: today)
    }
}
