// Picking rows, as in Things: swipe a row right to pick it and keep the finger down to pick the rows it passes over.
// While rows are picked the tab bar gives way to an action bar: Complete, Schedule, Move, More and Delete.
#if os(iOS)
import SwiftUI
import UIKit
import TaDaCore

enum PickSwipe {
    /// The coordinate space of a list's rows, which a swipe's location is read in.
    static let space = "PickSwipe"
    /// How far right a row must move to be picked.
    static let threshold: CGFloat = 64
    /// How far the row can move.
    static let reach: CGFloat = 88
}

extension View {
    /// A right swipe on this row picks it, then picks each row the finger moves onto.
    func swipeToPick(_ path: String) -> some View {
        modifier(SwipeToPick(path: path))
    }

    /// While rows are picked: Select All, the count and Done at the top, and the action bar instead of the tab bar.
    func pickingBars(model: AppModel) -> some View {
        modifier(PickingBars(model: model))
    }
}

private struct SwipeToPick: ViewModifier {
    let path: String
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme
    @State private var offset: CGFloat = 0
    @State private var hasPassed = false

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .leading) {
                if offset > 0 {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle").font(.system(size: 20, weight: .semibold))
                        Text("Pick").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: offset)
                    .frame(maxHeight: .infinity)
                    .background(theme.color(\.accent).opacity(hasPassed ? 1 : 0.6))
                    .clipped()
                    .accessibilityHidden(true)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(PickSwipe.space)) } action: { nav.rowFrames[path] = $0 }
            .gesture(PickPan(changed: changed, ended: ended))
            .accessibilityAction(named: "Pick") { nav.isPicking ? nav.togglePicked(path) : nav.startPicking(path) }
    }

    private func changed(_ translation: CGSize, _ location: CGPoint) {
        let x = max(translation.width, 0)
        offset = x <= PickSwipe.reach ? x : PickSwipe.reach + (x - PickSwipe.reach) / 4
        if !hasPassed, x >= PickSwipe.threshold {
            hasPassed = true
            if !nav.isPicking { nav.startPicking() }
            nav.pick(path, quietly: true)
            nav.play(.press)
        }
        guard hasPassed else { return }
        if let row = nav.pickable.first(where: { nav.rowFrames[$0]?.contains(CGPoint(x: 1, y: location.y)) == true }) {
            nav.pick(row)
        }
    }

    private func ended() {
        withAnimation(.snappy) { offset = 0 }
        hasPassed = false
    }
}

/// A pan that starts only when it moves right, away from the screen's left edge (the back swipe's), so the list
/// still scrolls and the back swipe still works.
private struct PickPan: UIGestureRecognizerRepresentable {
    let changed: (CGSize, CGPoint) -> Void
    let ended: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .began, .changed:
            let translation = pan.translation(in: pan.view)
            changed(CGSize(width: translation.x, height: translation.y), context.converter.location(in: .named(PickSwipe.space)))
        case .ended, .cancelled, .failed:
            ended()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            return velocity.x > 0 && velocity.x > abs(velocity.y) * 1.5 && pan.location(in: nil).x > 32
        }
    }
}

private struct PickingBars: ViewModifier {
    let model: AppModel
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .toolbar(nav.isPicking ? .hidden : .automatic, for: .tabBar)
            .navigationBarBackButtonHidden(nav.isPicking)
            .toolbar {
                if nav.isPicking {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Select All") { nav.pickAll() }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("\(nav.picked.count) Selected").font(.headline).foregroundStyle(theme.color(\.strong))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { nav.endPicking() }
                            .buttonStyle(.glassProminent)
                            .tint(theme.color(\.accent))
                    }
                    ToolbarItem(placement: .bottomBar) {
                        actions
                    }
                }
            }
    }

    private var tasks: [String] { nav.picked.filter { model.index[$0]?.properties.kind == .task } }

    private var actions: some View {
        let paths = nav.picked
        return HStack(spacing: 0) {
            action("Complete", "checkmark.circle", tint: \.done) {
                nav.play(.complete)
                let open = paths.filter { model.index[$0]?.properties.status != .done }
                nav.endPicking()
                Task { for path in open { await model.setStatus(.done, in: path) } }
            }
            action("Schedule", "calendar") { nav.sheet = .date(.due, paths: paths) }
            action("Move", "folder") { nav.sheet = .project(paths: tasks) }
                .disabled(tasks.isEmpty)
            Menu {
                Picker(selection: Binding<Status?> { nil } set: { status in
                    guard let status else { return }
                    nav.play(.pick)
                    nav.endPicking()
                    Task { for path in paths { await model.setStatus(status, in: path) } }
                }) {
                    ForEach(Status.menuOrder, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                } label: {
                    Label("Status", systemImage: "circle.dashed")
                }
                .pickerStyle(.menu)
                Button("Set Deadline…", systemImage: "flag") { nav.sheet = .date(.deadline, paths: paths) }
                Divider()
                if let vault = model.vault {
                    ShareLink(items: paths.map { vault.url(for: $0) }) {
                        Label("Share \(paths.count) File\(paths.count == 1 ? "" : "s")…", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                actionLabel("More", "ellipsis", tint: \.fg)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            action("Delete", "trash", tint: \.deadline) {
                nav.play(.trash)
                nav.endPicking()
                Task { await model.moveToTrash(paths) }
            }
        }
        .disabled(paths.isEmpty)
    }

    private func action(_ title: String, _ symbol: String, tint: KeyPath<Theme, PlatformColor> = \.fg,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) { actionLabel(title, symbol, tint: tint) }
            .buttonStyle(.plain)
    }

    private func actionLabel(_ title: String, _ symbol: String, tint: KeyPath<Theme, PlatformColor>) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 19)).frame(height: 24)
            Text(title).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(theme.color(tint))
        .frame(minWidth: 64, minHeight: 44)
        .contentShape(.rect)
    }
}
#endif
