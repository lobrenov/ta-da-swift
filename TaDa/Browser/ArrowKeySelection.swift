// Selection in the browser lists. A click opens a file; in lists that allow it, shift-click picks a range and
// ⌘-click adds or removes a task. Keys: ↑/↓ move the selection, ←/→ step the Agenda, Escape clears it, ⌫ or ⌘⌫ moves the selected file to
// the trash (in Trash, ⌘⌫ restores and ⌥⌘⌫ deletes forever). A key view behind each list takes the keyboard when the
// list appears, when nothing has it and when a row is picked. Keys reach it through the responder chain, so a text
// view (an editor, the title or the search field) with the keyboard keeps its own keys.
#if os(macOS)
import AppKit
import SwiftUI

extension View {
    /// Marks the browser list on screen; `paths` are its tasks from top to bottom. Rows show
    /// `model.isSelected(_:)` and call `model.click(_:)`.
    func arrowKeySelection(_ model: AppModel, paths: [String], allowsMultipleSelection: Bool = false) -> some View {
        modifier(ArrowKeyList(model: model, paths: paths, allowsMultipleSelection: allowsMultipleSelection))
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
    @State private var keys = WeakKeyView()

    func body(content: Content) -> some View {
        content
            .background(ListKeys(model: model, keys: keys).accessibilityHidden(true))
            .onChange(of: paths, initial: true) {
                model.arrowKeyList = AppModel.ArrowKeyList(id: id, paths: paths, allowsMultipleSelection: allowsMultipleSelection)
                model.keepPicked(in: paths)
            }
            // Picking a row gives the list the keyboard, from an editor too. Not for a new file, whose title is
            // about to take it.
            .onChange(of: model.selection) { _, selection in
                guard let selection, paths.contains(selection), model.titleFocus != selection else { return }
                keys.view?.takeKeyboard()
            }
            .onDisappear { if model.arrowKeyList?.id == id { model.arrowKeyList = nil } }
    }
}

private final class WeakKeyView {
    weak var view: ListKeyView?
}

/// Puts the list's key view behind it.
private struct ListKeys: NSViewRepresentable {
    let model: AppModel
    let keys: WeakKeyView

    func makeNSView(context: Context) -> ListKeyView {
        let view = ListKeyView(model: model)
        keys.view = view
        return view
    }

    func updateNSView(_ view: ListKeyView, context: Context) {}
}

/// The list's responder: ↑/↓, ←/→ and Escape arrive as move and cancel commands, ⌫ and ⌦ as key presses.
final class ListKeyView: NSView {
    let model: AppModel
    private var responders: NSKeyValueObservation?

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    /// Takes the keyboard when the list appears, and whenever nothing has it, as after an editor closes.
    /// Not from a text view, or for a new file, whose title is about to take it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        responders = window?.observe(\.firstResponder) { [weak self] window, _ in
            MainActor.assumeIsolated {
                if window.firstResponder === window { Task { self?.takeKeyboardIfFree() } }
            }
        }
        Task { [weak self] in self?.takeKeyboardIfFree() }
    }

    private func takeKeyboardIfFree() {
        guard let window, !(window.firstResponder is NSTextView), model.titleFocus == nil else { return }
        takeKeyboard()
    }

    func takeKeyboard() {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.specialKey == .delete || event.specialKey == .deleteForward, delete(event.modifierFlags) { return }
        interpretKeyEvents([event])
    }

    override func moveUp(_ sender: Any?) {
        model.moveSelection(by: -1)
    }

    override func moveDown(_ sender: Any?) {
        model.moveSelection(by: 1)
    }

    /// In the Agenda, ← and → step the day, or the week.
    override func moveLeft(_ sender: Any?) {
        if model.domain == .agenda, !model.isSearching { withAnimation(AgendaMotion.spring) { model.stepAgenda(by: -1) } } else { super.moveLeft(sender) }
    }

    override func moveRight(_ sender: Any?) {
        if model.domain == .agenda, !model.isSearching { withAnimation(AgendaMotion.spring) { model.stepAgenda(by: 1) } } else { super.moveRight(sender) }
    }

    override func cancelOperation(_ sender: Any?) {
        model.selection = nil
        model.clearMultiSelection()
        model.trashSelection = []
    }

    private func delete(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch flags.intersection([.command, .option, .control, .shift]) {
        case []: model.deleteKey(command: false)
        case .command: model.deleteKey(command: true)
        case [.command, .option]: model.deleteForeverKey()
        default: false
        }
    }
}
#endif
