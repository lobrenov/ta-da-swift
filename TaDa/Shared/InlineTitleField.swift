// A file's title in a list or header that turns into a text field when clicked: the project browser's title and the
// titles in a project's linked-tasks table.
import AppKit
import SwiftUI
import TaDaCore

/// Clicking the title edits it in place on `code`. Return or a click anywhere else in the window renames the file;
/// esc keeps the old title.
/// A file just created (`model.titleFocus`) starts out editing, its title selected.
struct InlineTitleField<Label: View>: View {
    let model: AppModel
    let path: String
    let height: CGFloat
    let font: Font
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
                    .onDisappear(perform: stopWatchingClicks)
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
        .onChange(of: model.titleFocus, initial: true) {
            guard model.titleFocus == path else { return }
            model.titleFocus = nil
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
        let new = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, new != title else { return }
        Task { await model.rename(path, to: new) }
    }
}
