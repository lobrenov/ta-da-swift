// The tocPanel on iPhone: a drawer from the right edge of a file screen with the file's headings, links and backlinks
// as an inset list. A swipe in from the screen's right edge opens it; swiping right or tapping the scrim closes it.
#if os(iOS)
import SwiftUI
import UIKit
import TaDaCore

extension View {
    /// The drawer over a file's page, and the edge swipe that opens it.
    func phoneTocDrawer(model: AppModel, document: OpenDocument, state: TocState, isSource: Bool, isSearching: Bool,
                        isActive: Bool, open: @escaping (String) -> Void) -> some View {
        modifier(PhoneTocDrawer(model: model, document: document, state: state, isSource: isSource, isSearching: isSearching,
                                isActive: isActive, open: open))
    }
}

struct PhoneTocDrawer: ViewModifier {
    let model: AppModel
    let document: OpenDocument
    let state: TocState
    let isSource: Bool
    let isSearching: Bool
    /// The screen is the one showing, with no sheet over it.
    let isActive: Bool
    let open: (String) -> Void
    /// VoiceOver's "Contents and Links" asked for the drawer.
    @State private var openRequested = false

    func body(content view: Content) -> some View {
        let toc = (model.index[document.path] ?? document.item).map { TocContent(item: $0, index: model.index) }
        let available = TocDrawerRules.isAvailable(toc, isSource: isSource, isSearching: isSearching)
        view
            .overlay {
                if available, let toc {
                    PhoneTocDrawerLayer(content: toc, state: state, isActive: isActive, openRequested: $openRequested, open: open)
                }
            }
            .onChange(of: document.path, initial: true) { state.visibleLines = 0...0 }
            .accessibilityActions {
                if available { Button("Contents and Links") { openRequested = true } }
            }
    }
}

/// The edge swipe, scrim and drawer. It holds the drawer's progress, so a drag redraws only this view.
private struct PhoneTocDrawerLayer: View {
    let content: TocContent
    let state: TocState
    let isActive: Bool
    @Binding var openRequested: Bool
    let open: (String) -> Void
    /// How far open the drawer is, 0 to 1.
    @State private var progress: CGFloat = 0
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            if isActive {
                RightEdgeSwipe(isClosed: progress == 0, onChange: { progress = $0 }, onEnd: settle)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            drawer(content)
        }
        .onChange(of: openRequested) { _, requested in
            guard requested else { return }
            openRequested = false
            withAnimation(.snappy) { progress = 1 }
        }
    }

    private func settle(velocity: CGFloat) {
        withAnimation(.snappy) { progress = TocDrawerRules.settlesOpen(progress: progress, velocity: velocity) ? 1 : 0 }
    }

    private func close() {
        withAnimation(.snappy) { progress = 0 }
    }

    private func drawer(_ toc: TocContent) -> some View {
        GeometryReader { viewport in
            let insets = viewport.safeAreaInsets
            ZStack(alignment: .trailing) {
                Color.black
                    .opacity((theme.isDark ? 0.5 : 0.25) * progress)
                    .contentShape(.rect)
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                list(toc, top: insets.top + 8, bottom: insets.bottom + 12)
                    .frame(width: TocDrawerRules.width)
                    .frame(maxHeight: .infinity)
                    .background(theme.color(theme.isDark ? \.side : \.bg),
                                in: UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 28))
                    .overlay(alignment: .leading) {
                        Capsule().fill(theme.color(\.surface)).frame(width: 5, height: 40).padding(.leading, 7)
                    }
                    .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.16), radius: 20, x: -12)
                    .offset(x: (1 - progress) * (TocDrawerRules.width + 40))
                    .simultaneousGesture(closeDrag)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .ignoresSafeArea()
            .allowsHitTesting(progress > 0)
            .accessibilityHidden(progress == 0)
            .accessibilityAddTraits(progress == 1 ? .isModal : [])
            .accessibilityAction(.escape, close)
        }
    }

    /// Dragging the drawer to the right closes it; a mostly vertical drag is left to the list.
    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                progress = TocDrawerRules.progress(start: 1, translation: drag.translation.width)
            }
            .onEnded { drag in settle(velocity: abs(drag.translation.width) > abs(drag.translation.height) ? drag.velocity.width : 0) }
    }

    private func list(_ toc: TocContent, top: CGFloat, bottom: CGFloat) -> some View {
        let current = toc.currentHeading(lastVisibleLine: state.visibleLines.upperBound)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !toc.headings.isEmpty {
                    section("Contents", count: nil) {
                        ForEach(Array(toc.headings.enumerated()), id: \.offset) { index, heading in
                            row(heading.text, indent: 28 + CGFloat(toc.depth(of: heading)) * 18, isCurrent: index == current) {
                                state.scroll.toLine(heading.line)
                                close()
                            }
                        }
                    }
                }
                files("Links", toc.links)
                files("Backlinks", toc.backlinks)
            }
            .padding(.top, top)
            .padding(.bottom, bottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Contents and links")
    }

    @ViewBuilder private func files(_ name: String, _ files: [TocFile]) -> some View {
        if !files.isEmpty {
            section(name, count: files.count) {
                ForEach(files) { file in
                    row(file.title, indent: 28, icon: file.icon, hint: file.hint, isUnresolved: file.path == nil) {
                        guard let path = file.path else { return }
                        close()
                        open(path)
                    }
                }
            }
        }
    }

    private func section(_ title: String, count: Int?, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title.uppercased()).tracking(0.26)
                if let count { Text("\(count)") }
            }
            .scaledFont(size: 13, weight: .medium)
            .foregroundStyle(theme.color(\.muted))
            .padding(.leading, 28)
            .padding(.trailing, 22)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
            rows()
        }
        .padding(.bottom, 18)
    }

    private func row(_ title: String, indent: CGFloat, icon: LinkChoice.Icon? = nil, hint: String = "", isCurrent: Bool = false,
                     isUnresolved: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    LinkChoiceIcon(icon: icon, search: Self.search, theme: theme)
                        .frame(width: 20)
                        .opacity(isUnresolved ? 0.6 : 1)
                }
                Text(title)
                    .strikethrough(isUnresolved)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !hint.isEmpty {
                    Text(hint).scaledFont(size: 15).foregroundStyle(theme.color(\.muted))
                }
            }
            .scaledFont(size: 17, weight: isCurrent ? .semibold : .regular)
            .foregroundStyle(theme.color(isUnresolved ? \.muted : isCurrent ? \.accent : \.fg))
            .padding(.leading, indent)
            .padding(.trailing, 22)
            .scaledMinHeight(44)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.color(\.border)).frame(height: 0.5) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isUnresolved)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private static let search = LinkMenuSearch()
}

/// A leftward pan that starts at the window's right edge, recognised on the window.
private struct RightEdgeSwipe: UIViewRepresentable {
    /// The drawer is closed, so a swipe may open it.
    let isClosed: Bool
    /// The drawer's progress as the finger moves.
    let onChange: (CGFloat) -> Void
    /// The swipe ended with this horizontal velocity.
    let onEnd: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.coordinator = context.coordinator
        return anchor
    }

    func updateUIView(_ anchor: Anchor, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.install(in: anchor.window)
    }

    static func dismantleUIView(_ anchor: Anchor, coordinator: Coordinator) {
        coordinator.install(in: nil)
    }

    /// Puts the recognizer on the window once the view is in one.
    final class Anchor: UIView {
        var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.install(in: window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: RightEdgeSwipe?
        let recognizer = UIPanGestureRecognizer()
        private var startX: CGFloat = 0

        override init() {
            super.init()
            recognizer.delegate = self
            recognizer.addTarget(self, action: #selector(pan))
        }

        /// Moves the recognizer to `window`, or takes it off with nil.
        func install(in window: UIWindow?) {
            guard recognizer.view !== window else { return }
            if let old = recognizer.view {
                old.removeGestureRecognizer(recognizer)
            }
            if let window {
                window.addGestureRecognizer(recognizer)
            }
        }

        @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
            guard let parent else { return }
            switch recognizer.state {
            case .changed:
                parent.onChange(TocDrawerRules.progress(start: 0, translation: recognizer.translation(in: recognizer.view).x))
            case .ended, .cancelled:
                parent.onEnd(recognizer.velocity(in: recognizer.view).x)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let parent, parent.isClosed, let window = recognizer.view else { return false }
            return TocDrawerRules.startsOpening(startX: startX, windowWidth: window.bounds.width,
                                                velocity: recognizer.velocity(in: window))
        }

        /// Not while a sheet or alert is over the screen.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window = gestureRecognizer.view as? UIWindow, window.rootViewController?.presentedViewController == nil else { return false }
            startX = touch.location(in: window).x
            return true
        }

        /// The page's and the editor's scrolling wait for the swipe to fail, so they don't scroll while the drawer drags.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}
#endif
