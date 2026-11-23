// The iPhone formatting keyboard: markdown keys in place of the system keyboard, swapped in by the keyboard bar's Aa.
// Keys with a corner mark have variants: press and hold opens them above the key, slide to one and let go; letting go
// on the line's own variant changes nothing.
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
        [.heading, .bold, .italic, .strikethrough, .highlight],
        [.list, .subtask, .quote, .callout, .divider],
        [.code, .link, .table, .outdent, .indent],
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
        case .subtask, .callout, .divider, .link, .table, .outdent, .indent: false
        }
    }

    private func tap(_ id: KeyID) {
        taps += 1
        perform(id.action)
    }

    /// A tap performs the key; held, its variants open and the one under the finger is performed on release.
    private func press(_ id: KeyID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if holdTask == nil, hold == nil {
                    holdTask = Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled, !id.variants.isEmpty else { return }
                        hold = Hold(key: id, highlight: id.current(state.line) ?? 0)
                        holds += 1
                    }
                }
                if let current = hold, let frame = keyFrames[id] {
                    let layout = stripLayout(count: id.variants.count, above: frame, width: keyboardWidth)
                    let index = Int(((value.location.x - layout.minX - Self.stripPadding) / Self.cellStride).rounded(.down))
                    hold = Hold(key: current.key, highlight: min(max(index, 0), id.variants.count - 1))
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                holdTask = nil
                if let hold {
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

    private var keyboardWidth: CGFloat { (keyFrames[.indent]?.maxX ?? 384) + 6 }

    // MARK: Variants

    private static let cellWidth: CGFloat = 46
    private static let cellStride: CGFloat = 48
    private static let stripPadding: CGFloat = 6
    private static let stripHeight: CGFloat = 50 + 12 + 26

    /// The strip's frame: centred over the key and kept on screen; below the key when there's no room above it.
    private func stripLayout(count: Int, above key: CGRect, width: CGFloat) -> CGRect {
        let stripWidth = Self.stripPadding * 2 + CGFloat(count) * Self.cellStride - 2
        let x = min(max(key.midX - stripWidth / 2, 6), width - 6 - stripWidth)
        let y = key.minY - 4 - Self.stripHeight >= 0 ? key.minY - 4 - Self.stripHeight : key.maxY + 4
        return CGRect(x: x, y: y, width: stripWidth, height: Self.stripHeight)
    }

    private func variants(_ hold: Hold, above key: CGRect, width: CGFloat) -> some View {
        let variants = hold.key.variants
        let layout = stripLayout(count: variants.count, above: key, width: width)
        let current = hold.key.current(state.line)
        let highlighted = variants[hold.highlight]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Self.cellStride - Self.cellWidth) {
                ForEach(Array(variants.enumerated()), id: \.offset) { index, variant in
                    glyph(variant.glyph, size: 19)
                        .foregroundStyle(theme.color(\.strong))
                        .frame(width: Self.cellWidth, height: 50)
                        .background(index == hold.highlight ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 12))
                        .overlay(alignment: .bottom) {
                            if index == current {
                                Circle().fill(theme.color(\.accent)).frame(width: 4, height: 4).padding(.bottom, 4)
                            }
                        }
                }
            }
            HStack(spacing: 8) {
                Text(highlighted.label).fontWeight(.semibold).foregroundStyle(theme.color(\.strong))
                Text(verbatim: highlighted.hint)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(theme.color(\.muted))
            }
            .font(.system(size: 15))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 26)
        }
        .padding(Self.stripPadding)
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .glassEffect(in: .rect(cornerRadius: 18))
        .offset(x: layout.minX, y: layout.minY)
        .allowsHitTesting(false)
    }

    // MARK: Glyphs

    @ViewBuilder
    private func glyph(_ glyph: Glyph, size: CGFloat) -> some View {
        switch glyph {
        case let .symbol(name):
            Image(systemName: name).font(.system(size: size))
        case let .text(text):
            Text(verbatim: text).font(.system(size: size * 0.85, weight: .semibold))
        case let .mono(text):
            Text(verbatim: text).font(.system(size: size * 0.7, weight: .semibold, design: .monospaced))
        case let .box(marker):
            InlineCheckboxView(marker: marker, tint: theme.checkboxTint(marker), background: theme.bg)
                .frame(width: size, height: size)
        case let .callout(type):
            CalloutIconView(type: type, tint: theme.calloutTint(type))
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
    /// Its markdown, named under the strip.
    let hint: String
    let glyph: Glyph
    let action: FormattingAction
    var id: String { label }
}

private enum KeyID: Hashable {
    case heading, bold, italic, strikethrough, highlight
    case list, subtask, quote, callout, divider
    case code, link, table, outdent, indent

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
        }
    }

    var isStructural: Bool { self == .outdent || self == .indent }

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
        }
    }

    static let subtaskStates: [(String, Character)] = [
        ("To do", " "), ("Doing", "/"), ("Done", "x"), ("Cancelled", "-"), ("Forwarded", ">"), ("Scheduling", "<"),
    ]
    static let calloutTypes: [CalloutType] = [.note, .tip, .info, .todo, .warning, .quote]

    var variants: [Variant] {
        switch self {
        case .heading:
            (1...6).map { Variant(label: "Heading \($0)", hint: String(repeating: "#", count: $0), glyph: .text("H\($0)"), action: .line(.heading($0))) }
        case .list:
            [Variant(label: "Bulleted list", hint: "-", glyph: .symbol("list.bullet"), action: .line(.bulletedList)),
             Variant(label: "Numbered list", hint: "1.", glyph: .symbol("list.number"), action: .line(.numberedList))]
        case .subtask:
            Self.subtaskStates.map { Variant(label: $0.0, hint: "[\($0.1)]", glyph: .box($0.1), action: .line(.box($0.1))) }
        case .callout:
            Self.calloutTypes.map { Variant(label: $0.title, hint: "> [!\($0.rawValue)]", glyph: .callout($0), action: .callout($0)) }
        case .code:
            [Variant(label: "Inline code", hint: "`", glyph: .symbol("chevron.left.forwardslash.chevron.right"), action: .inline(.code)),
             Variant(label: "Code block", hint: "```", glyph: .symbol("terminal"), action: .block(.codeBlock))]
        case .link:
            [Variant(label: "Wikilink", hint: "[[ ]]", glyph: .mono("[[ ]]"), action: .wikiLink),
             Variant(label: "Link", hint: "[ ]( )", glyph: .symbol("link"), action: .link),
             Variant(label: "Embed", hint: "![[ ]]", glyph: .symbol("photo"), action: .embed)]
        case .bold, .italic, .strikethrough, .highlight, .quote, .divider, .table, .outdent, .indent:
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
