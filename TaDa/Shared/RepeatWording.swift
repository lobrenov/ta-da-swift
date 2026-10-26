// What the status menus, rows and chips say about a repeating task, on the Mac and iPhone.
import SwiftUI
import TaDaCore

enum RepeatWording {
    /// "tomorrow", "today", or "Mon 9 Nov" (with the year when it isn't this year's).
    static func day(_ date: LocalDate, today: LocalDate) -> String {
        switch today.days(to: date) {
        case 0: "today"
        case 1: "tomorrow"
        default: date.relativeLabel(today: today)
        }
    }

    /// A status row's name: Cancelled is "Skip this time" on a repeating task.
    static func title(of status: Status, repeating: Bool) -> String {
        repeating && status == .cancelled ? "Skip this time" : status.rawValue
    }

    /// What Done or Skip does to a repeating task: "moves to Mon 9 Nov", or "ends the repeat".
    static func note(_ move: RepeatMove, today: LocalDate) -> String {
        switch move {
        case .moves(let date): "moves to \(day(date, today: today))"
        case .ends: "ends the repeat"
        }
    }

    /// How the status menus word `items`: `repeating` only when every one is a task whose rule reads, and a `move` only
    /// when they would all move to the same date, or all end.
    static func statusContext(of items: [Item], index: VaultIndex, today: LocalDate) -> (repeating: Bool, move: RepeatMove?) {
        let repeating = !items.isEmpty && items.allSatisfy { $0.properties.kind == .task && $0.properties.repeatRule?.rule != nil }
        let moves = Set(items.map { index.repeatMove(of: $0, today: today, completing: true) })
        return (repeating, repeating && moves.count == 1 ? moves.first ?? nil : nil)
    }

    /// A status box's tooltip and spoken name: "Skip this time · moves to Mon 9 Nov". Without a `move` only the name.
    static func statusHelp(_ status: Status, repeating: Bool, move: RepeatMove?, today: LocalDate) -> String {
        let name = title(of: status, repeating: repeating)
        guard repeating, status.isClosed, let move else { return name }
        return "\(name) · \(note(move, today: today))"
    }

    /// A row's text after the repeat glyph for a done or skipped task waiting to move: "Tomorrow" or "Ended".
    static func rowNext(_ move: RepeatMove, today: LocalDate) -> String {
        switch move {
        case .moves(let date): day(date, today: today).capitalizedFirst
        case .ends: "Ended"
        }
    }

    /// "Repeats every week on Monday until Sun 20 Dec".
    private static func ruleText(_ rule: RepeatRule, today: LocalDate) -> String {
        "Repeats " + rule.description { $0.year == today.year ? $0.formatted(.weekdayDayMonth) : $0.formatted(.weekdayDayMonthYear) }
            .lowercasedFirst
    }

    /// A row glyph's tooltip and spoken label: "Repeats every week on Monday", with where a done task moves.
    static func rowHelp(_ rule: Repeat, move: RepeatMove?, today: LocalDate) -> String {
        guard let readable = rule.rule else { return "Repeats \(rule.text)" }
        let spelled = ruleText(readable, today: today)
        switch move {
        case .moves(let date)?: return "\(spelled) · moves to \(day(date, today: today)) when the day changes"
        case .ends?: return "\(spelled) · the repeat ends, logged when the day changes"
        case nil: return spelled
        }
    }

    /// The chip that carries a task's rule: the due chip, or the deadline chip when there's a deadline and no due date.
    static func chipKind(of properties: Properties) -> AgendaEntry.Kind? {
        guard properties.kind == .task, properties.repeatRule != nil else { return nil }
        return properties.dueDate == nil && properties.deadline != nil ? .deadline : .due
    }

    /// A due or deadline chip's tooltip: the rule spelled out and, for a rule that reads, the next date.
    static func chipHelp(_ rule: Repeat, next: RepeatMove?, today: LocalDate) -> String {
        guard let readable = rule.rule else { return "Ta Da can't read this rule, so the task doesn't repeat" }
        let spelled = ruleText(readable, today: today)
        guard case .moves(let date)? = next else { return spelled }
        return "\(spelled) · next \(date.relativeLabel(today: today))"
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

/// A date chip's repeat suffix in `muted`: a dot, the repeat glyph and the rule's frequency ("Weekly"), or for a rule that
/// can't be read a `blocked` warning glyph and the rule as written. `iconSize` is the glyph's size.
struct RepeatChipSuffix: View {
    let rule: Repeat
    let iconSize: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Text("·")
            if rule.rule == nil {
                glyph("exclamationmark.triangle.fill").foregroundStyle(theme.color(\.blocked))
            } else {
                glyph("repeat")
            }
            Text(rule.rule?.frequencyLabel ?? rule.text)
        }
        .foregroundStyle(theme.color(\.muted))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rule.rule.map { "Repeats \($0.frequencyLabel)" } ?? "Can't read the rule \(rule.text)")
    }

    private func glyph(_ name: String) -> some View {
        let image = Image(systemName: name)
        #if os(iOS)
        return image.scaledFont(size: iconSize)
        #else
        return image.font(.system(size: iconSize))
        #endif
    }
}
