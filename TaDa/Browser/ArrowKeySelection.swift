// Selection in the browser lists. A click opens a file; in lists that allow it, shift-click picks a range and
// ⌘-click adds or removes a task. Keys: ↑/↓ move the selection, Escape clears it, ⌫ or ⌘⌫ moves the selected file to
// the trash (in Trash, ⌘⌫ restores and ⌥⌘⌫ deletes forever). They act only while no text view (an editor,
// the title or the search field) has the keyboard and no file menu is open, so those keep their own keys.
// A key monitor on the main window rather than SwiftUI focus: a focusable list never gets focus there.
import AppKit
import SwiftUI

extension View {
    /// Marks the browser list on screen; `paths` are its tasks from top to bottom. Rows show
    /// `model.isSelected(_:)` and call `model.click(_:)`.
    func arrowKeySelection(_ model: AppModel, paths: [String], allowsMultipleSelection: Bool = false) -> some View {
        modifier(ArrowKeyList(model: model, paths: paths, allowsMultipleSelection: allowsMultipleSelection))
    }

    /// Handles the arrow keys in the window this view is in.
    func arrowKeyMonitor(_ model: AppModel) -> some View {
        modifier(ArrowKeyMonitor(model: model))
    }
}

extension AppModel {
    /// A click on a row in the browser list on screen. Shift-click picks a range and ⌘-click adds or removes
    /// the row, where the list allows several; otherwise the file opens (in Trash, only it is picked).
    func click(_ path: String) {
        let modifiers = NSEvent.modifierFlags
        if arrowKeyList?.allowsMultipleSelection == true, modifiers.contains(.shift) {
            extendSelection(to: path)
        } else if arrowKeyList?.allowsMultipleSelection == true, modifiers.contains(.command) {
            toggleSelection(path)
        } else {
            selectOnly(path)
        }
    }
}

private struct ArrowKeyList: ViewModifier {
    let model: AppModel
    let paths: [String]
    let allowsMultipleSelection: Bool
    /// Lists replace each other (Upcoming changes layout); only the one that set the order clears it.
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: paths, initial: true) {
                model.arrowKeyList = AppModel.ArrowKeyList(id: id, paths: paths, allowsMultipleSelection: allowsMultipleSelection)
                model.keepPicked(in: paths)
            }
            .onDisappear { if model.arrowKeyList?.id == id { model.arrowKeyList = nil } }
    }
}

private struct ArrowKeyMonitor: ViewModifier {
    let model: AppModel
    @State private var window = WeakWindow()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .background(WindowReader(window: window))
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    handle(event) ? nil : event
                }
                // The window gives the search field the keyboard when it opens; the arrow keys come first.
                Task { if !model.isSearching { releaseKeyboard(fieldEditorsOnly: true) } }
            }
            // Picking a row in the list hands it the arrow keys: the editor lets go of the keyboard.
            // Not for a new file, whose title is about to take it.
            .onChange(of: model.selection) { _, selection in
                guard let selection, model.arrowKeyList?.paths.contains(selection) == true,
                      model.titleFocus != selection else { return }
                releaseKeyboard(fieldEditorsOnly: false)
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private func releaseKeyboard(fieldEditorsOnly: Bool) {
        guard let window = window.value, let text = window.firstResponder as? NSTextView,
              text.isFieldEditor || !fieldEditorsOnly else { return }
        window.makeFirstResponder(nil)
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window = window.value, event.window === window, !(window.firstResponder is NSTextView),
              !FileMenu.shared.isOpen else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 51 || event.keyCode == 117 {
            switch modifiers {
            case []: return model.deleteKey(command: false)
            case .command: return model.deleteKey(command: true)
            case [.command, .option]: return model.deleteForeverKey()
            default: return false
            }
        }
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 125: return model.moveSelection(by: 1)
        case 126: return model.moveSelection(by: -1)
        case 53:
            if model.selection != nil || !model.multiSelection.isEmpty {
                model.selection = nil
                model.clearMultiSelection()
            } else if !model.trashSelection.isEmpty {
                model.trashSelection = []
            } else {
                return false
            }
            return true
        default: return false
        }
    }
}

private final class WeakWindow {
    weak var value: NSWindow?
}

/// Reports the window it's placed in.
private struct WindowReader: NSViewRepresentable {
    let window: WeakWindow

    func makeNSView(context: Context) -> NSView { Reader(window: window) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Reader: NSView {
        let box: WeakWindow
        init(window: WeakWindow) {
            box = window
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() { box.value = window }
    }
}
