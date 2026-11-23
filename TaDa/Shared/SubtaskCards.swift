// The "From notes" group: open subtask lines from notes (and dated or filed lines in any file) as one card per source
// file, after a page's own tasks. A line has a tickable box, its text (which opens the file at that line), its date and
// parent, and the subtasks glyph when boxes are nested under it.
import SwiftUI
import TaDaCore

struct SubtaskCards: View {
    /// Where the cards show, which decides the date pill: the Agenda day flags only an overdue date; a week, a project,
    /// an area and Loose tasks show it.
    enum Context {
        case agendaDay, agendaWeek, page
    }

    let model: AppModel
    let cards: [SubtaskCard]
    var context = Context.page
    /// The project or area whose page shows the cards: its chip is left out.
    var parent: Item? = nil
    @State private var ticked: Set<Tick> = []
    #if os(iOS)
    @Environment(PhoneNavigation.self) private var nav
    #endif
    @Environment(\.theme) private var theme

    private struct Tick: Hashable {
        var path: String
        var line: Int
    }

    var body: some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.gap) {
                CountGroupHeader(title: "From notes", count: cards.reduce(0) { $0 + $1.lines.count })
                ForEach(cards) { card($0) }
            }
            #if os(iOS)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            #endif
        }
    }

    private func card(_ card: SubtaskCard) -> some View {
        let item = model.index[card.path]
        return VStack(alignment: .leading, spacing: 2) {
            Button { openFile(card.path) } label: {
                HStack(spacing: 8) {
                    NoteIcon(tint: \.link)
                    Text(card.title).cardFont(Metrics.title, weight: .semibold).foregroundStyle(theme.color(\.strong)).lineLimit(1)
                    Spacer(minLength: 8)
                    if !card.folder.isEmpty {
                        Text(card.folder).cardFont(Metrics.folder).foregroundStyle(theme.color(\.muted)).lineLimit(1)
                    }
                }
                .frame(minHeight: Metrics.rowHeight - 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(card.title), \(card.lines.count) subtasks")
            .accessibilityHint("Opens the file")
            ForEach(card.lines, id: \.lineIndex) { line($0, in: card.path, item: item) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(\.side), in: .rect(cornerRadius: Metrics.radius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(theme.color(\.border)))
    }

    private func line(_ box: Checkbox, in path: String, item: Item?) -> some View {
        let isTicked = ticked.contains(Tick(path: path, line: box.lineIndex))
        let hasChildren = item.map { Self.hasChildren(box, in: $0) } ?? false
        let place = box.parent.flatMap { model.index.parentItem(titled: $0) }
        return HStack(spacing: 10) {
            Button { tick(box, in: path) } label: { boxView(box, isTicked: isTicked) }
                .buttonStyle(.plain)
                .disabled(isTicked)
                .accessibilityLabel("Complete \(box.title)")
            Button { open(box, in: path) } label: {
                Text(box.title)
                    .cardFont(Metrics.text)
                    .strikethrough(isTicked)
                    .foregroundStyle(theme.color(isTicked ? \.muted : \.fg))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: Metrics.rowHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the file at this line")
            if hasChildren {
                Image(systemName: "checklist").cardFont(Metrics.folder).foregroundStyle(theme.color(\.muted))
                    .accessibilityLabel("Has subtasks")
            }
            if let due = box.due, showsDate(due) { datePill(due) }
            if let place, place.path != parent?.path { parentChip(place) }
        }
        .contextMenu {
            Button("Open at Line") { open(box, in: path) }
            Button("Mark Done") { tick(box, in: path) }
            Button("Mark Cancelled") { setMarker("-", of: box, in: path) }
        }
    }

    private func boxView(_ box: Checkbox, isTicked: Bool) -> some View {
        let isDoing = box.marker == "/" && !isTicked
        let tint: KeyPath<Theme, PlatformColor> = isTicked ? \.done : isDoing ? \.doing : \.muted
        return RoundedRectangle(cornerRadius: Metrics.box / 4.5)
            .strokeBorder(theme.color(tint), lineWidth: 1.5)
            .background(isTicked ? theme.color(tint) : .clear, in: .rect(cornerRadius: Metrics.box / 4.5))
            .frame(width: Metrics.box, height: Metrics.box)
            .overlay {
                if isTicked {
                    Image(systemName: "checkmark").font(.system(size: Metrics.box * 0.55, weight: .heavy)).foregroundStyle(theme.color(\.bg))
                } else if isDoing {
                    RoundedRectangle(cornerRadius: 1.5).fill(theme.color(tint)).frame(width: Metrics.box * 0.37, height: Metrics.box * 0.37)
                }
            }
            .frame(minWidth: Metrics.rowHeight - 6, minHeight: Metrics.rowHeight)
            .contentShape(.rect)
    }

    private func showsDate(_ due: LocalDate) -> Bool {
        context != .agendaDay || due < model.today
    }

    private func datePill(_ due: LocalDate) -> some View {
        let overdue = due < model.today
        let tint = theme.color(overdue ? \.deadline : \.accent)
        return Text(due.rowLabel(today: model.today))
            .cardFont(Metrics.folder)
            .foregroundStyle(overdue ? tint : theme.color(\.fg))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(theme.isDark ? 0.22 : 0.14), in: .capsule)
            .fixedSize()
            .accessibilityLabel("Due \(due.relativeLabel(today: model.today))\(overdue ? ", overdue" : "")")
    }

    private func parentChip(_ place: Item) -> some View {
        HStack(spacing: 4) {
            if place.properties.kind == .area {
                AreaIcon(size: 12)
            } else {
                ProgressRing(model.index.progress(of: place)).foregroundStyle(theme.color(\.link))
                    .scaleEffect(12 / 14).frame(width: 12, height: 12)
            }
            Text(place.title).cardFont(Metrics.folder).foregroundStyle(theme.color(\.link)).lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("In \(place.title)")
    }

    /// Whether a box is nested under `box`: the next box in the file is.
    static func hasChildren(_ box: Checkbox, in item: Item) -> Bool {
        guard let i = item.checkboxes.firstIndex(where: { $0.lineIndex == box.lineIndex }), i + 1 < item.checkboxes.count else { return false }
        return item.checkboxes[i + 1].isNested
    }

    private func tick(_ box: Checkbox, in path: String) {
        ticked.insert(Tick(path: path, line: box.lineIndex))
        Task { await model.tick(box, in: path) }
    }

    private func setMarker(_ marker: Character, of box: Checkbox, in path: String) {
        ticked.insert(Tick(path: path, line: box.lineIndex))
        Task { await model.setMarker(marker, of: box, in: path) }
    }

    private func open(_ box: Checkbox, in path: String) {
        model.open(box, in: path)
        #if os(iOS)
        nav.push(.file(path))
        #endif
    }

    private func openFile(_ path: String) {
        #if os(macOS)
        model.selection = path
        #else
        nav.push(.file(path))
        #endif
    }

    private enum Metrics {
        #if os(macOS)
        static let box: CGFloat = 16, rowHeight: CGFloat = 30, radius: CGFloat = 7, gap: CGFloat = 8
        static let title = 13.5 as CGFloat, text = 13.5 as CGFloat, folder = 12 as CGFloat
        #else
        static let box: CGFloat = 22, rowHeight: CGFloat = 44, radius: CGFloat = 14, gap: CGFloat = 8
        static let title = 15 as CGFloat, text = 17 as CGFloat, folder = 13 as CGFloat
        #endif
    }
}

private extension View {
    /// The system font at `size` points, scaling with Dynamic Type on the iPhone.
    func cardFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        #if os(iOS)
        scaledFont(size: size, weight: weight)
        #else
        font(.system(size: size, weight: weight))
        #endif
    }
}
