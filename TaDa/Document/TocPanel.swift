// The tocPanel: a file's headings, the files its body links to and the files linking to it. On the Mac a rail
// at the Live editor's right edge opens it as a panel; `TocContent` is what both list.
import SwiftUI
import TaDaCore
#if os(macOS)
import AppKit
#endif

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
    /// The body's H1 to H6; the file's title isn't one.
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
        headings = item.headings
        links = index.links(from: item).map { link in
            link.item.map(file) ?? TocFile(title: link.title, path: nil, icon: .note, hint: "")
        }
        backlinks = index.backlinks(to: item).map(file)
    }

    /// A heading's depth: its level below the shallowest level in the file.
    func depth(of heading: Heading) -> Int {
        heading.level - (headings.map(\.level).min() ?? heading.level)
    }

    /// A file with no headings and no links has no rail.
    var hasRail: Bool { !headings.isEmpty || !links.isEmpty || !backlinks.isEmpty }

    var hasLinks: Bool { !links.isEmpty || !backlinks.isEmpty }

    /// The heading in view: the last whose line is at or above the last visible line.
    func currentHeading(lastVisibleLine: Int) -> Int? {
        headings.lastIndex { $0.line <= lastVisibleLine }
    }
}

/// What the Live editor reports to the rail and panel, and how they ask it to scroll.
@Observable
final class TocState {
    /// The 0-based first and last lines of the editor's visible area.
    var visibleLines = 0...0
    /// The body changed and the pointer hasn't moved since.
    var typing = false
    @ObservationIgnored let scroll = EditorScroll()
    /// The open panel's frame in the window's SwiftUI space (origin top-left); nil while it's closed.
    @ObservationIgnored var panelFrame: CGRect?

    /// Whether a point in window coordinates (an event's `locationInWindow`, origin bottom-left) is over the open panel.
    func panelContains(_ windowPoint: CGPoint) -> Bool {
        #if os(macOS)
        guard let panelFrame, let content = NSApp.keyWindow?.contentView else { return false }
        let point = content.convert(windowPoint, from: nil)
        return panelFrame.contains(CGPoint(x: point.x, y: content.isFlipped ? point.y : content.bounds.height - point.y))
        #else
        return false
        #endif
    }
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

    /// How close to the window's right edge a touch starts a swipe that opens the drawer.
    static let edgeZone: CGFloat = 24

    /// A touch within the edge zone, moving left more than up or down.
    static func startsOpening(startX: CGFloat, windowWidth: CGFloat, velocity: CGPoint) -> Bool {
        windowWidth - startX <= edgeZone && velocity.x < 0 && abs(velocity.x) > abs(velocity.y)
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
import AppKit

extension View {
    /// The rail and panel over the document's scroll view at the editor's right edge.
    func tocPanel(model: AppModel, document: OpenDocument, state: TocState) -> some View {
        modifier(TocPanelModifier(model: model, document: document, state: state))
    }
}

/// The rail and panel over a document's scroll view. `isOpen` is the one animated value: it slides the mounted panel in from the
/// editor's right edge and fades it, and fades the rail out. One hover zone in the overlay decides whether the pointer is
/// inside, from the rail's and the panel's resting frames, and one cancellable task opens or closes after a delay.
private struct TocPanelModifier: ViewModifier {
    let model: AppModel
    let document: OpenDocument
    let state: TocState
    @State private var isOpen = false
    /// What the pointer last asked for; `isOpen` follows it after a delay.
    @State private var wantsOpen = false
    @State private var pending: Task<Void, Never>?
    @State private var railFrame = CGRect.zero
    @State private var panelFrame = CGRect.zero
    @State private var panelGlobalFrame = CGRect.zero

    private static let space = "tocPanel"
    private static let openDelay = Duration.milliseconds(50)
    private static let closeDelay = Duration.milliseconds(200)
    private static let slideIn = Animation.smooth(duration: 0.22)
    private static let slideOut = Animation.smooth(duration: 0.16)
    private static let panelWidth: CGFloat = 260
    private static let panelTrailing: CGFloat = 12
    /// How far past the rail's own padding the pointer still counts as on it.
    private static let railSlack: CGFloat = 4

    func body(content view: Content) -> some View {
        let toc = (model.index[document.path] ?? document.item).map { TocContent(item: $0, index: model.index) }
        view
            .coordinateSpace(.named(Self.space))
            .onContinuousHover { phase in
                if case .active = phase, state.typing { state.typing = false }
            }
            .onChange(of: document.path, initial: true) {
                state.typing = false
                state.visibleLines = 0...0
            }
            .onChange(of: state.typing) { _, typing in
                guard typing else { return }
                pending?.cancel()
                wantsOpen = false
                isOpen = false
            }
            .onChange(of: isOpen) { publishPanelFrame() }
            .onChange(of: panelGlobalFrame) { publishPanelFrame() }
            .onDisappear {
                pending?.cancel()
                state.panelFrame = nil
            }
            .overlay {
                if let toc, toc.hasRail { overlay(toc) }
            }
    }

    private func overlay(_ toc: TocContent) -> some View {
        let current = toc.currentHeading(lastVisibleLine: state.visibleLines.upperBound)
        return GeometryReader { viewport in
            panelStack(toc, current: current, viewport: viewport.size)
                .contentShape(Path(hoverZone))
                .onContinuousHover { phase in
                    switch phase {
                    case .active: setWantsOpen(true)
                    case .ended: setWantsOpen(false)
                    }
                }
        }
    }

    /// The hover area, in the overlay's space: the rail while closed, the rail and the panel's resting frame while open.
    private var hoverZone: CGRect {
        let rail = railFrame.insetBy(dx: -Self.railSlack, dy: -Self.railSlack)
        return isOpen ? rail.union(panelFrame) : rail
    }

    private func panelStack(_ toc: TocContent, current: Int?, viewport: CGSize) -> some View {
        ZStack(alignment: .topTrailing) {
            TocRail(content: toc, current: current)
                .opacity(isOpen || state.typing ? 0 : 1)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { railFrame = $0 }
                .padding(.top, 50)
                .padding(.trailing, 10)
                .allowsHitTesting(false)
            TocPanel(content: toc, current: current, maxHeight: viewport.height - 46 - 12,
                     scroll: state.scroll.toLine, open: { model.openLink(to: $0) })
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { panelFrame = $0 }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { panelGlobalFrame = $0 }
                .offset(x: isOpen ? 0 : Self.panelWidth + Self.panelTrailing)
                .opacity(isOpen ? 1 : 0)
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
                .padding(.top, 46)
                .padding(.trailing, Self.panelTrailing)
        }

        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    /// Records what the pointer wants and, if that differs from what's shown, opens or closes after a delay. A later change of mind
    /// cancels the wait.
    private func setWantsOpen(_ wants: Bool) {
        guard wants != wantsOpen else { return }
        wantsOpen = wants
        pending?.cancel()
        guard wants != isOpen else { return }
        pending = Task {
            try? await Task.sleep(for: wants ? Self.openDelay : Self.closeDelay)
            guard !Task.isCancelled else { return }
            withAnimation(wants ? Self.slideIn : Self.slideOut) { isOpen = wants }
        }
    }

    /// The cursor's exclusion zone: the panel's resting frame while it's open.
    private func publishPanelFrame() {
        state.panelFrame = isOpen ? panelGlobalFrame : nil
    }
}

/// Sizes its one child to its own ideal height, no taller than `max`; the panel's content height from the first frame.
private struct CappedHeight: Layout {
    let max: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let ideal = view.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: ideal.width, height: Swift.min(ideal.height, max))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
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
                    .frame(width: content.depth(of: heading) == 0 ? 16 : 10, height: 2)
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
    @Environment(\.theme) private var theme

    var body: some View {
        CappedHeight(max: maxHeight) {
            ScrollView { list }.scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 260)
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

    private var list: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !content.headings.isEmpty {
                label("Contents", count: nil)
                ForEach(Array(content.headings.enumerated()), id: \.offset) { index, heading in
                    TocRow(title: heading.text, indent: CGFloat(content.depth(of: heading)) * 14, isCurrent: index == current) {
                        scroll(heading.line)
                    }
                }
            }
            section("Links", content.links, separated: !content.headings.isEmpty)
            section("Backlinks", content.backlinks, separated: !content.headings.isEmpty || !content.links.isEmpty)
        }
        .padding(4)
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
