// The floating panel the global hotkey opens over any app. It takes the keyboard without bringing Ta Da forward.
#if os(macOS)
import AppKit
import SwiftUI
import TaDaCore

/// Opens Quick Entry centred on the screen with the pointer, on every Space, with a new draft each time. It closes on
/// esc, the hotkey again, or when another window takes the keyboard.
final class QuickEntryPanel: NSObject, NSWindowDelegate {
    private let model: AppModel
    private(set) var panel: NSPanel?
    /// The panel's top edge, kept as its content grows or shrinks.
    private var top: CGFloat = 0

    init(model: AppModel) {
        self.model = model
    }

    var isOpen: Bool { panel != nil }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickEntryContent(model: model, create: { [weak self] draft, opening in
            self?.create(draft, opening: opening)
        }, close: { [weak self] in self?.close() }))
        let size = panel.contentView?.fittingSize ?? CGSize(width: 560, height: 200)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        }
        top = panel.frame.maxY
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel, panel.frame.maxY != top else { return }
        panel.setFrameOrigin(CGPoint(x: panel.frame.minX, y: top - panel.frame.height))
    }

    /// Writes the file; when `opening`, brings Ta Da forward and shows it there.
    func create(_ draft: QuickEntryDraft, opening: Bool) {
        close()
        Task { [model] in
            guard let path = await model.create(draft), opening else { return }
            NSApp.activate()
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
            model.openLink(to: path)
        }
    }

    /// A borderless panel that can take the keyboard.
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}

/// Holds the draft for one opening of the panel.
private struct QuickEntryContent: View {
    let model: AppModel
    let create: (QuickEntryDraft, Bool) -> Void
    let close: () -> Void
    @State private var draft = QuickEntryDraft()

    var body: some View {
        QuickEntryView(model: model, draft: $draft, create: { create(draft, $0) }, close: close)
            .themed(by: model)
    }
}
#endif
