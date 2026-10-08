// A file's title in a list or header that turns into a text field when clicked: the project browser's title and the
// titles in a project's linked-tasks table.
import SwiftUI
import TaDaCore

/// Clicking the title edits it in place on `code`. Return or clicking away renames the file; esc keeps the old title.
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
                    .onAppear { focused = true }
                    .padding(.horizontal, 6)
                    .frame(height: height)
                    .background(theme.color(\.code), in: .rect(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)))
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

    private func commit() {
        editing = false
        let new = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, new != title else { return }
        Task { await model.rename(path, to: new) }
    }
}
