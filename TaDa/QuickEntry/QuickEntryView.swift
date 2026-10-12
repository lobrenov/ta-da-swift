// Quick Entry's content: the type switch, the title, the file it will write, and the keys and buttons in the footer.
#if os(macOS)
import SwiftUI
import TaDaCore

struct QuickEntryView: View {
    let model: AppModel
    @Binding var draft: QuickEntryDraft
    /// Creates the file; true also opens it in Ta Da.
    let create: (_ opening: Bool) -> Void
    let close: () -> Void
    @FocusState private var titleFocused: Bool
    @Environment(\.theme) private var theme

    private var canCreate: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                typeSwitch
                TextField("Title", text: $draft.title, prompt: Text("New \(draft.kind.rawValue)").foregroundStyle(theme.color(\.muted)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.color(\.strong))
                    .frame(minHeight: 30)
                    .focused($titleFocused)
                if draft.kind == .area {
                    Text("An area has only its name and tags: no status, parent or dates.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.color(\.muted))
                }
                if canCreate { fileLine }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 16)
            footer
        }
        .frame(width: 560)
        .background(theme.color(theme.isDark ? \.side : \.bg), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.color(\.surface)))
        .foregroundStyle(theme.color(\.fg))
        .font(.system(size: 13))
        .background {
            Button("Close", action: close)
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Entry")
        .onAppear { titleFocused = true }
    }

    private var typeSwitch: some View {
        HStack(spacing: 2) {
            ForEach([Item.Kind.task, .project, .area], id: \.self) { kind in
                let isOn = draft.kind == kind
                Button {
                    draft = draft.changingKind(to: kind)
                } label: {
                    HStack(spacing: 6) {
                        icon(kind)
                        Text(kind.rawValue.capitalized)
                    }
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(theme.color(isOn ? \.strong : \.muted))
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(isOn ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 6))
                    .shadow(color: .black.opacity(isOn ? 0.18 : 0), radius: 1, y: 1)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(theme.color(\.code), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.color(\.border)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Type")
    }

    @ViewBuilder
    private func icon(_ kind: Item.Kind) -> some View {
        switch kind {
        case .task:
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(theme.color(\.muted), lineWidth: 1.3)
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
        case .project:
            ProgressRing(fraction: 0.25)
                .foregroundStyle(theme.color(\.accent))
                .scaleEffect(12 / 14)
                .frame(width: 12, height: 12)
        case .area:
            AreaIcon(size: 12)
        }
    }

    /// The file to be written, and a warning when its name is taken and gets a number.
    @ViewBuilder
    private var fileLine: some View {
        let path = model.quickEntryPath(for: draft)
        let name = FileNaming.sanitise(draft.title)
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.system(size: 10))
                .accessibilityHidden(true)
            Text(path)
                .font(.system(size: 11, design: .monospaced))
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.color(\.muted))
        let numbered = Item.title(ofPath: path)
        if numbered != name {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .accessibilityHidden(true)
                Text("There’s already a \(draft.kind.rawValue) called \(name). This one will be \(numbered).")
            }
            .font(.system(size: 12))
            .foregroundStyle(theme.color(\.blocked))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            let hints = draft.kind == .area ? [("esc", "Close")] : [("⇧⌘M", "Move"), ("⌘S", "Due"), ("⌘D", "Deadline")]
            ForEach(hints, id: \.0) { hint in
                MenuKeyHint(key: hint.0, label: hint.1, theme: theme)
            }
            .accessibilityHidden(true)
            Spacer()
            Button { create(true) } label: { buttonLabel("Create and Open", key: "⌘↵") }
                .buttonStyle(ActionButtonStyle(height: 28, fill: \.code))
                .keyboardShortcut(.return, modifiers: .command)
            Button { create(false) } label: { buttonLabel("Create", key: "↵") }
                .buttonStyle(ActionButtonStyle(kind: .primary, height: 28))
                .keyboardShortcut(.defaultAction)
        }
        .disabled(!canCreate)
        .font(.system(size: 11))
        .foregroundStyle(theme.color(\.muted))
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(theme.color(theme.isDark ? \.bg : \.side))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 11, bottomTrailingRadius: 11))
        .overlay(alignment: .top) { Hairline() }
    }

    private func buttonLabel(_ title: String, key: String) -> some View {
        HStack(spacing: 7) {
            Text(title)
            Text(key)
                .font(.system(size: 10.5, design: .monospaced))
                .opacity(0.7)
        }
    }
}
#endif
