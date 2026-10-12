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
        super.init()
        // The panel, or one of its menus, losing the keyboard: a click in another app or another Ta Da window.
        NotificationCenter.default.addObserver(self, selector: #selector(keyLeft), name: NSWindow.didResignKeyNotification, object: nil)
    }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    /// Shows the panel with a new view, so the last opening's view goes outside its own callbacks.
    func open() {
        let panel = panel ?? makePanel()
        model.quickEntryDraft = QuickEntryDraft()
        panel.contentView = NSHostingView(rootView: QuickEntryContent(model: model, create: { [weak self, model] opening in
            self?.create(model.quickEntryDraft, opening: opening)
        }, close: { [weak self] in self?.close() }))
        let size = panel.contentView?.fittingSize ?? CGSize(width: 560, height: 200)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        }
        top = panel.frame.maxY
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        PropertyPicker.shared.close(path: AppModel.quickEntryDraftPath)
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        self.panel = panel
        return panel
    }

    /// Closes once neither the panel nor one of its menus has the keyboard; a menu with a search field takes it.
    @objc private func keyLeft(_ notification: Notification) {
        guard let panel, let window = notification.object as? NSWindow, window === panel || window.parent === panel else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, panel.isVisible, !panel.isKeyWindow, panel.childWindows?.contains(where: \.isKeyWindow) != true else { return }
            close()
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel, panel.isVisible, panel.frame.maxY != top else { return }
        panel.setFrameOrigin(CGPoint(x: panel.frame.minX, y: top - panel.frame.height))
    }

    /// Writes the file; when `opening`, brings Ta Da forward and shows it there. A failure brings Ta Da forward to show
    /// its error.
    func create(_ draft: QuickEntryDraft, opening: Bool) {
        close()
        Task { [model] in
            guard let path = await model.create(draft) else { return NSApp.activate() }
            guard opening else { return }
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

/// Reads the taken names for one opening of the panel.
private struct QuickEntryContent: View {
    let model: AppModel
    let create: (Bool) -> Void
    let close: () -> Void
    /// Read once per opening: nothing else writes while the panel has the keyboard.
    @State private var taken: [Item.Kind: Set<String>] = [:]

    var body: some View {
        QuickEntryView(model: model, taken: taken, create: create, close: close)
            .onAppear { taken = model.quickEntryTakenNames() }
            .themed(by: model)
    }
}
#endif
