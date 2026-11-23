// The iPhone formatting keyboard: markdown keys in place of the system keyboard, swapped in by the keyboard bar's Aa.
// Keys with a corner mark have variants: press and hold grows a panel of them out of the key, slide to one and let go;
// letting go on the line's own variant changes nothing. Delete repeats while held.
#if os(iOS)
import SwiftUI
import TaDaCore

/// The formats at the caret, which the keyboard rings. The keyboard bar keeps it current.
@Observable final class FormattingState {
    var line = LineFormat.state(of: "")
    var inline: Set<LineFormat.Inline> = []
}

/// What a key does; the keyboard bar performs it on the editor.
enum FormattingAction: Equatable {
    case line(LineFormat)
    /// Makes the line a subtask, or ticks it, as the bar's subtask key does.
    case subtask
    case inline(LineFormat.Inline)
    /// A block slash command (code block, divider, table) on a line of its own.
    case block(SlashCommand)
    case callout(CalloutType)
    case wikiLink, link, embed
    case outdent, indent
    case deleteBackward
}

struct FormattingKeyboard: View {
    let theme: Theme
    let state: FormattingState
    let haptics: Bool
    let perform: (FormattingAction) -> Void

    @State private var keyFrames: [KeyID: CGRect] = [:]
    @State private var hold: Hold?
    @State private var holdTask: Task<Void, Never>?
    @State private var taps = 0
    @State private var holds = 0

    private static let rows: [[KeyID]] = [
        [.heading, .bold, .italic, .strikethrough],
        [.list, .subtask, .quote, .callout],
        [.highlight, .code, .link, .table],
        [.divider, .outdent, .indent, .delete],
    ]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 7) {
                ForEach(Self.rows, id: \.self) { row in
                    HStack(spacing: 7) {
                        ForEach(row, id: \.self) { key($0) }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .overlay(alignment: .topLeading) {
                if let hold, let frame = keyFrames[hold.key] {
                    variants(hold, above: frame, width: proxy.size.width)
                }
            }
        }
        .coordinateSpace(.named(Self.space))
        .sensoryFeedback(.impact(weight: .light), trigger: taps) { _, _ in haptics }
        .sensoryFeedback(.impact(weight: .medium), trigger: holds) { _, _ in haptics }
    }

    private static let space = "formattingKeyboard"

    // MARK: Keys

    private func key(_ id: KeyID) -> some View {
        let isActive = isActive(id)
        return glyph(id.glyph(state.line), size: 21)
            .foregroundStyle(isActive ? theme.color(\.accent) : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(id.isStructural ? Self.altKey : Self.key, in: .rect(cornerRadius: 10))
            .overlay {
                if isActive || hold?.key == id {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.accent), lineWidth: 2)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !id.variants.isEmpty {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.secondary)
                        .padding(7)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
            .contentShape(.rect)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { keyFrames[id] = $0 }
            .gesture(press(id))
            .accessibilityElement()
            .accessibilityLabel(id.label)
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { tap(id) }
            .accessibilityActions {
                ForEach(id.variants) { variant in
                    Button(variant.label) { perform(variant.action) }
                }
            }
    }

    private func isActive(_ id: KeyID) -> Bool {
        switch id {
        case .heading: state.line.heading != nil
        case .list: state.line.list != nil
        case .quote: state.line.quote
        case .bold: state.inline.contains(.bold)
        case .italic: state.inline.contains(.italic)
        case .strikethrough: state.inline.contains(.strikethrough)
        case .highlight: state.inline.contains(.highlight)
        case .code: state.inline.contains(.code)
        case .subtask, .callout, .divider, .link, .table, .outdent, .indent, .delete: false
        }
    }

    private func tap(_ id: KeyID) {
        taps += 1
        perform(id.action)
    }

    /// A tap performs the key; held, its variants open and the one under the finger is performed on release. Delete
    /// performs on touch down and repeats while held.
    private func press(_ id: KeyID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if holdTask == nil, hold == nil {
                    if id == .delete { tap(id) }
                    holdTask = Task {
                        try? await Task.sleep(for: .milliseconds(id == .delete ? 450 : 350))
                        if id == .delete {
                            while !Task.isCancelled {
                                perform(id.action)
                                try? await Task.sleep(for: .milliseconds(90))
                            }
                        }
                        guard !Task.isCancelled, !id.variants.isEmpty else { return }
                        hold = Hold(key: id, highlight: id.current(state.line) ?? 0)
                        holds += 1
                    }
                }
                if let current = hold, let frame = keyFrames[id] {
                    let layout = panelLayout(count: id.variants.count, key: frame, width: keyboardWidth)
                    let index = Int(((value.location.x - layout.minX - Self.panelPadding) / Self.cellStride).rounded(.down))
                    hold = Hold(key: current.key, highlight: min(max(index, 0), id.variants.count - 1))
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                holdTask = nil
                if id == .delete {
                    // Performed on touch down.
                } else if let hold {
                    // The line's own variant keeps the line as it is.
                    if hold.highlight != id.current(state.line) {
                        taps += 1
                        perform(id.variants[hold.highlight].action)
                    }
                } else {
                    tap(id)
                }
                hold = nil
            }
    }

    private var keyboardWidth: CGFloat { (keyFrames[.delete]?.maxX ?? 384) + 6 }

    // MARK: Variants

    private static let cellWidth: CGFloat = 52
    private static let cellStride: CGFloat = 56
    private static let panelPadding: CGFloat = 8
    private static let panelHeight: CGFloat = 56 + 16

    /// The panel's frame: centred over the key and kept on screen, over the row above; below the key on the top row.
    private func panelLayout(count: Int, key: CGRect, width: CGFloat) -> CGRect {
        let panelWidth = Self.panelPadding * 2 + CGFloat(count) * Self.cellStride - (Self.cellStride - Self.cellWidth)
        let x = min(max(key.midX - panelWidth / 2, 6), width - 6 - panelWidth)
        let y = key.minY - 6 - Self.panelHeight >= 0 ? key.minY - 6 - Self.panelHeight : key.maxY + 6
        return CGRect(x: x, y: y, width: panelWidth, height: Self.panelHeight)
    }

    /// The panel grows out of the key in the key's fill; the variant under the finger fills in `accent`.
    private func variants(_ hold: Hold, above key: CGRect, width: CGFloat) -> some View {
        let variants = hold.key.variants
        let layout = panelLayout(count: variants.count, key: key, width: width)
        let current = hold.key.current(state.line)
        let neck = layout.minY < key.minY
            ? CGRect(x: key.minX, y: layout.maxY - 10, width: key.width, height: key.maxY - layout.maxY + 10)
            : CGRect(x: key.minX, y: key.minY, width: key.width, height: layout.minY - key.minY + 10)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Self.key)
                .frame(width: neck.width, height: neck.height)
                .offset(x: neck.minX, y: neck.minY)
            HStack(spacing: Self.cellStride - Self.cellWidth) {
                ForEach(Array(variants.enumerated()), id: \.offset) { index, variant in
                    let isHighlighted = index == hold.highlight
                    glyph(variant.glyph, size: 21, onAccent: isHighlighted)
                        .foregroundStyle(isHighlighted ? theme.color(\.bg) : Color.primary)
                        .frame(width: Self.cellWidth, height: 56)
                        .background(isHighlighted ? theme.color(\.accent) : .clear, in: .rect(cornerRadius: 10))
                        .overlay(alignment: .bottom) {
                            if index == current {
                                Circle().fill(isHighlighted ? theme.color(\.bg) : Color.secondary)
                                    .frame(width: 4, height: 4).padding(.bottom, 5)
                            }
                        }
                }
            }
            .padding(Self.panelPadding)
            .frame(width: layout.width, height: layout.height, alignment: .leading)
            .background(Self.key, in: .rect(cornerRadius: 16))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            .offset(x: layout.minX, y: layout.minY)
        }
        .allowsHitTesting(false)
    }

    // MARK: Glyphs

    @ViewBuilder
    private func glyph(_ glyph: Glyph, size: CGFloat, onAccent: Bool = false) -> some View {
        switch glyph {
        case let .symbol(name):
            Image(systemName: name).font(.system(size: size))
        case let .text(text):
            Text(verbatim: text).font(.system(size: size * 0.85, weight: .semibold))
        case let .mono(text):
            Text(verbatim: text).font(.system(size: size * 0.7, weight: .semibold, design: .monospaced))
        case let .box(marker):
            InlineCheckboxView(marker: marker, tint: onAccent ? theme.bg : theme.checkboxTint(marker),
                               background: onAccent ? theme.accent : theme.bg)
                .frame(width: size, height: size)
        case let .callout(type):
            CalloutIconView(type: type, tint: onAccent ? theme.bg : theme.calloutTint(type))
                .frame(width: size, height: size)
        }
    }

    /// The system keyboard's key fills.
    private static let key = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white })
    private static let altKey = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1)
    })
}

private struct Hold: Equatable {
    let key: KeyID
    let highlight: Int
}

private enum Glyph: Equatable {
    case symbol(String), text(String), mono(String), box(Character), callout(CalloutType)
}

private struct Variant: Identifiable {
    let label: String
    let glyph: Glyph
    let action: FormattingAction
    var id: String { label }
}

private enum KeyID: Hashable {
    case heading, bold, italic, strikethrough, highlight
    case list, subtask, quote, callout, divider
    case code, link, table, outdent, indent, delete

    var label: String {
        switch self {
        case .heading: "Heading"
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .highlight: "Highlight"
        case .list: "Bulleted list"
        case .subtask: "Subtask"
        case .quote: "Quote"
        case .callout: "Callout"
        case .divider: "Divider"
        case .code: "Inline code"
        case .link: "Wikilink"
        case .table: "Table"
        case .outdent: "Outdent"
        case .indent: "Indent"
        case .delete: "Delete"
        }
    }

    var isStructural: Bool { self == .outdent || self == .indent || self == .delete }

    /// The subtask key shows the caret line's box.
    func glyph(_ line: LineFormat.State) -> Glyph {
        switch self {
        case .heading: .text("H1")
        case .bold: .symbol("bold")
        case .italic: .symbol("italic")
        case .strikethrough: .symbol("strikethrough")
        case .highlight: .symbol("highlighter")
        case .list: .symbol("list.bullet")
        case .subtask: line.box.map(Glyph.box) ?? .symbol("checkmark.square")
        case .quote: .symbol("text.quote")
        case .callout: .symbol("text.bubble")
        case .divider: .symbol("minus")
        case .code: .symbol("chevron.left.forwardslash.chevron.right")
        case .link: .mono("[[ ]]")
        case .table: .symbol("tablecells")
        case .outdent: .symbol("decrease.indent")
        case .indent: .symbol("increase.indent")
        case .delete: .symbol("delete.left")
        }
    }

    var action: FormattingAction {
        switch self {
        case .heading: .line(.heading(1))
        case .bold: .inline(.bold)
        case .italic: .inline(.italic)
        case .strikethrough: .inline(.strikethrough)
        case .highlight: .inline(.highlight)
        case .list: .line(.bulletedList)
        case .subtask: .subtask
        case .quote: .line(.quote)
        case .callout: .callout(.note)
        case .divider: .block(.divider)
        case .code: .inline(.code)
        case .link: .wikiLink
        case .table: .block(.table)
        case .outdent: .outdent
        case .indent: .indent
        case .delete: .deleteBackward
        }
    }

    static let subtaskStates: [(String, Character)] = [
        ("To do", " "), ("Doing", "/"), ("Done", "x"), ("Cancelled", "-"), ("Forwarded", ">"), ("Scheduling", "<"),
    ]
    static let calloutTypes: [CalloutType] = [.note, .tip, .info, .todo, .warning, .quote]

    var variants: [Variant] {
        switch self {
        case .heading:
            (1...6).map { Variant(label: "Heading \($0)", glyph: .text("H\($0)"), action: .line(.heading($0))) }
        case .list:
            [Variant(label: "Bulleted list", glyph: .symbol("list.bullet"), action: .line(.bulletedList)),
             Variant(label: "Numbered list", glyph: .symbol("list.number"), action: .line(.numberedList))]
        case .subtask:
            Self.subtaskStates.map { Variant(label: $0.0, glyph: .box($0.1), action: .line(.box($0.1))) }
        case .callout:
            Self.calloutTypes.map { Variant(label: $0.title, glyph: .callout($0), action: .callout($0)) }
        case .code:
            [Variant(label: "Inline code", glyph: .symbol("chevron.left.forwardslash.chevron.right"), action: .inline(.code)),
             Variant(label: "Code block", glyph: .symbol("terminal"), action: .block(.codeBlock))]
        case .link:
            [Variant(label: "Wikilink", glyph: .mono("[[ ]]"), action: .wikiLink),
             Variant(label: "Link", glyph: .symbol("link"), action: .link),
             Variant(label: "Embed", glyph: .symbol("photo"), action: .embed)]
        case .bold, .italic, .strikethrough, .highlight, .quote, .divider, .table, .outdent, .indent, .delete:
            []
        }
    }

    /// The variant the caret's line already has, which gets a dot.
    func current(_ line: LineFormat.State) -> Int? {
        switch self {
        case .heading: line.heading.map { $0 - 1 }
        case .list: line.list.map { $0 == .bulletedList ? 0 : 1 }
        case .subtask: line.box.flatMap { box in Self.subtaskStates.firstIndex { $0.1 == (box == "X" ? "x" : box) } }
        default: nil
        }
    }
}
#endif
