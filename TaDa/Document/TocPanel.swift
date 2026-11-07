// The tocPanel: a file's headings, the files its body links to and the files linking to it. On the Mac a rail
// at the Live editor's right edge opens it as a panel; `TocContent` is what both list.
import SwiftUI
import TaDaCore

/// A file listed under Links or Backlinks: the file it opens, or an unresolved link's title.
struct TocFile: Identifiable, Equatable {
    var title: String
    /// Nil for an unresolved link.
    var path: String?
    var icon: LinkChoice.Icon
    /// Project or Area; empty for the rest.
    var hint: String
    var id: String { path ?? "unresolved:" + title.lowercased() }
}

/// The sections of a file's tocPanel.
struct TocContent: Equatable {
    /// The body's H2 to H6; the file's title and an H1 aren't listed.
    var headings: [Heading]
    var links: [TocFile]
    var backlinks: [TocFile]

    init(headings: [Heading], links: [TocFile], backlinks: [TocFile]) {
        self.headings = headings
        self.links = links
        self.backlinks = backlinks
    }

    init(item: Item, index: VaultIndex) {
        let search = LinkMenuSearch()
        search.source.index = index
        func file(_ item: Item) -> TocFile {
            let choice = search.choice(item)
            let kind = item.properties.kind
            return TocFile(title: item.title, path: item.path, icon: choice.icon,
                           hint: kind == .project ? "Project" : kind == .area ? "Area" : "")
        }
        headings = item.headings.filter { $0.level >= 2 }
        links = index.links(from: item).map { link in
            link.item.map(file) ?? TocFile(title: link.title, path: nil, icon: .note, hint: "")
        }
        backlinks = index.backlinks(to: item).map(file)
    }

    /// A file with no headings and no links has no rail.
    var hasRail: Bool { !headings.isEmpty || !links.isEmpty || !backlinks.isEmpty }

    var hasLinks: Bool { !links.isEmpty || !backlinks.isEmpty }

    /// The heading in view: the last whose line is at or above the top visible line.
    func currentHeading(topLine: Int) -> Int? {
        headings.lastIndex { $0.line <= topLine }
    }
}

/// What the Live editor reports to the rail and panel, and how they ask it to scroll.
@Observable
final class TocState {
    /// The 0-based line at the top of the editor's visible area.
    var topLine = 0
    /// The body changed and the pointer hasn't moved since.
    var typing = false
    @ObservationIgnored let scroll = EditorScroll()
}

/// How the iPhone drawer opens and settles.
enum TocDrawerRules {
    static let width: CGFloat = 318
    /// A swipe faster than this (points per second) settles the drawer the way it points.
    static let flick: CGFloat = 400

    /// A file with something to list gets the drawer in Live mode, unless the search is showing.
    static func isAvailable(_ content: TocContent?, isSource: Bool, isSearching: Bool) -> Bool {
        content?.hasRail == true && !isSource && !isSearching
    }

    /// How far open (0 to 1) a drag of `translation` leaves a drawer that started at `start`.
    static func progress(start: CGFloat, translation: CGFloat) -> CGFloat {
        min(1, max(0, start - translation / width))
    }

    /// Whether the drawer settles open: by the swipe's direction when it's a flick, else by which half it's in.
    static func settlesOpen(progress: CGFloat, velocity: CGFloat) -> Bool {
        abs(velocity) > flick ? velocity < 0 : progress > 0.5
    }
}

#if os(macOS)

extension View {
    /// The rail and panel over the document's scroll view at the editor's right edge.
    func tocPanel(model: AppModel, document: OpenDocument, state: TocState) -> some View {
        modifier(TocPanelModifier(model: model, document: document, state: state))
    }
}

private struct TocPanelModifier: ViewModifier {
    let model: AppModel
    let document: OpenDocument
    let state: TocState

    func body(content view: Content) -> some View {
        let toc = (model.index[document.path] ?? document.item).map { TocContent(item: $0, index: model.index) }
        view
            .onContinuousHover { phase in
                if case .active = phase, state.typing { state.typing = false }
            }
            .onChange(of: document.path, initial: true) {
                state.typing = false
                state.topLine = 0
            }
            .overlay {
                if let toc, toc.hasRail {
                    TocOverlay(content: toc, state: state, open: { model.openLink(to: $0) })
                }
            }
    }
}

/// The rail, and over it the panel while the pointer rests on either.
private struct TocOverlay: View {
    let content: TocContent
    let state: TocState
    let open: (String) -> Void
    @State private var isOpen = false
    @State private var overRail = false
    @State private var overPanel = false
    @State private var pending: Task<Void, Never>?
    @Environment(\.theme) private var theme

    static let openDelay = Duration.milliseconds(150)
    static let closeDelay = Duration.milliseconds(300)
    static let fade = 0.12

    var body: some View {
        GeometryReader { viewport in
            ZStack(alignment: .topTrailing) {
                TocRail(content: content, current: content.currentHeading(topLine: state.topLine))
                    .opacity(isOpen || state.typing ? 0 : 1)
                    .onHover { overRail = $0 }
                    .allowsHitTesting(!state.typing)
                    .padding(.top, 50)
                    .padding(.trailing, 10)
                if isOpen {
                    TocPanel(content: content, current: content.currentHeading(topLine: state.topLine),
                             maxHeight: viewport.size.height - 46 - 12, scroll: state.scroll.toLine, open: open)
                        .onHover { overPanel = $0 }
                        .padding(.top, 46)
                        .padding(.trailing, 12)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .animation(.easeOut(duration: Self.fade), value: isOpen)
        .onChange(of: overRail || overPanel) { _, inside in
            pending?.cancel()
            guard inside != isOpen else { return }
            pending = Task {
                try? await Task.sleep(for: inside ? Self.openDelay : Self.closeDelay)
                guard !Task.isCancelled else { return }
                isOpen = inside
            }
        }
        .onChange(of: state.typing) { _, typing in
            guard typing else { return }
            pending?.cancel()
            overRail = false
            overPanel = false
            isOpen = false
        }
    }
}

/// A dash per heading, the section in view in `accent`, then a link mark when there are links.
struct TocRail: View {
    let content: TocContent
    let current: Int?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 9) {
            ForEach(Array(content.headings.enumerated()), id: \.offset) { index, heading in
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.color(index == current ? \.accent : \.surface))
                    .frame(width: heading.level == 2 ? 16 : 10, height: 2)
            }
            if content.hasLinks {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.color(\.surface))
                    .padding(.top, content.headings.isEmpty ? 0 : 4)
            }
        }
        .padding(8)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Contents and links")
    }
}

/// The popup panel's chrome round Contents, Links and Backlinks.
struct TocPanel: View {
    let content: TocContent
    let current: Int?
    let maxHeight: CGFloat
    let scroll: (Int) -> Void
    let open: (String) -> Void
    @State private var height: CGFloat = 0
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                if !content.headings.isEmpty {
                    label("Contents", count: nil)
                    ForEach(Array(content.headings.enumerated()), id: \.offset) { index, heading in
                        TocRow(title: heading.text, indent: CGFloat(heading.level - 2) * 14, isCurrent: index == current) {
                            scroll(heading.line)
                        }
                    }
                }
                section("Links", content.links, separated: !content.headings.isEmpty)
                section("Backlinks", content.backlinks, separated: !content.headings.isEmpty || !content.links.isEmpty)
            }
            .padding(4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 260, height: min(height, maxHeight))
        .font(.system(size: 13))
        .background(theme.color(theme.isDark ? \.side : \.bg), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.surface)))
        .shadow(color: theme.isDark ? .black.opacity(0.5) : Color(red: 70 / 255, green: 55 / 255, blue: 20 / 255).opacity(0.18),
                radius: 22, y: 18)
        .shadow(color: theme.isDark ? .black.opacity(0.3) : Color(red: 70 / 255, green: 55 / 255, blue: 20 / 255).opacity(0.1),
                radius: 4, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Contents and links")
    }

    @ViewBuilder
    private func section(_ name: String, _ files: [TocFile], separated: Bool) -> some View {
        if !files.isEmpty {
            if separated {
                Hairline()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .accessibilityHidden(true)
            }
            label(name, count: files.count)
            ForEach(files) { file in
                TocRow(title: file.title, icon: file.icon, hint: file.hint, isUnresolved: file.path == nil) {
                    if let path = file.path { open(path) }
                }
            }
        }
    }

    private func label(_ text: String, count: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
            if let count {
                Text("\(count)").font(.system(size: 10.5, weight: .medium))
            }
        }
        .foregroundStyle(theme.color(\.muted))
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A heading or a file in the panel.
private struct TocRow: View {
    let title: String
    var indent: CGFloat = 0
    var icon: LinkChoice.Icon?
    var hint = ""
    var isCurrent = false
    var isUnresolved = false
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.theme) private var theme
    private static let search = LinkMenuSearch()

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                LinkChoiceIcon(icon: icon, search: Self.search, theme: theme)
                    .frame(width: 14)
                    .opacity(isUnresolved ? 0.6 : 1)
            }
            Text(title)
                .strikethrough(isUnresolved)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
            }
        }
        .fontWeight(isCurrent ? .semibold : .regular)
        .foregroundStyle(theme.color(isUnresolved ? \.muted : isCurrent ? \.accent : hovered ? \.strong : \.fg))
        .padding(.leading, 8 + indent)
        .padding(.trailing, 8)
        .frame(height: 26)
        .background(hovered ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
    }
}
#endif
