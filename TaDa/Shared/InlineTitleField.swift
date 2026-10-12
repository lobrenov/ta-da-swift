// A file's title in a list or header that turns into a text field when clicked: the project browser's title and the
// titles in a project's linked-tasks table.
#if os(macOS)
import AppKit
import SwiftUI
import TaDaCore

/// Clicking the title edits it in place on `code`. Return or a click anywhere else in the window renames the file;
/// esc keeps the old title.
/// A file just created (`model.titleFocus`, or `focus`) starts out editing, its title selected. A notes folder's name
/// passes its own `rename` and no `focus`.
struct InlineTitleField<Label: View>: View {
    let model: AppModel
    let path: String
    let height: CGFloat
    let font: Font
    /// The model's request to start editing this title; nil for none.
    var focus: ReferenceWritableKeyPath<AppModel, String?>? = \.titleFocus
    /// Renames from the new title; by default, the file at `path`.
    var rename: ((String) async -> Void)? = nil
    /// Starts out editing, and runs `onEnd` once editing ends, also when the field goes away while editing, which then
    /// renames: the sidebar's folder name field.
    var onEnd: (() -> Void)? = nil
    /// The title as it shows when not editing.
    @ViewBuilder var label: Label
    @State private var draft = ""
    @State private var editing = false
    @FocusState private var focused: Bool
    @State private var anchor = ScreenAnchor()
    /// Ends editing on a click outside the field, which a click on text or empty space wouldn't otherwise do.
    @State private var clickMonitor: Any?
    @Environment(\.theme) private var theme

    private var title: String { Item.title(ofPath: path) }

    var body: some View {
        Group {
            if editing {
                TextField("Title", text: $draft)
                    .textFieldStyle(.plain)
                    .font(font)
                    .foregroundStyle(theme.color(\.strong))
                    .focused($focused)
                    .onSubmit { focused = false }
                    .onExitCommand {
                        draft = title
                        focused = false
                    }
                    .onChange(of: focused) { if !focused { commit() } }
                    .onAppear(perform: watchClicks)
                    // Takes the keyboard once the field is in the window.
                    .task {
                        while anchor.window == nil, !Task.isCancelled { await Task.yield() }
                        focused = true
                    }
                    .onDisappear {
                        stopWatchingClicks()
                        if onEnd != nil, editing { commit() }
                    }
                    .padding(.horizontal, 6)
                    .frame(height: height)
                    .background(theme.color(\.code), in: .rect(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)))
                    .background(ScreenAnchorReader(anchor: anchor))
                    .accessibilityLabel("Title")
            } else {
                Button(action: begin) {
                    label
                        .font(font)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(height: height)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Click to rename")
                .accessibilityHint("Renames the file")
                .pointerStyle(.horizontalText)
            }
        }
        .padding(.leading, -6)
        .onAppear { if onEnd != nil, !editing { begin() } }
        .onChange(of: focus.flatMap { model[keyPath: $0] }, initial: true) {
            guard let focus, model[keyPath: focus] == path else { return }
            model[keyPath: focus] = nil
            begin()
        }
    }

    private func begin() {
        draft = title
        editing = true
    }

    private func watchClicks() {
        stopWatchingClicks()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated {
                if let window = event.window, window === anchor.window,
                   !anchor.rect.contains(window.convertPoint(toScreen: event.locationInWindow)) {
                    focused = false
                }
            }
            return event
        }
    }

    private func stopWatchingClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func commit() {
        editing = false
        onEnd?()
        let new = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, new != title else { return }
        Task {
            if let rename { await rename(new) } else { await model.rename(path, to: new) }
        }
    }
}
#endif
