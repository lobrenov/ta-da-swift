// The only file that imports TaDaMarkdown.
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import TaDaMarkdown
import TaDaCore

struct LiveEditor: View {
    @Binding var text: String
    let theme: Theme
    let documentID: String
    /// Titles that links can resolve to, matched case-insensitively.
    var linkTargets: Set<String> = []
    var fitsContent = false
    var autocomplete = Autocomplete()
    /// Plays a light tap when a task box is toggled (iOS).
    var haptics = false
    var header: AnyView? = nil
    /// Receives the link target (`[[Target|alias]]` reports `Target`).
    var onLinkClick: (String) -> Void = { _ in }

    @State private var slashCommand = SlashCommandProxy()
    #if os(macOS)
    @State private var slashMenu = SlashMenuController()
    @State private var checkboxMenu = CheckboxMenuController()
    @State private var calloutMenu = CalloutMenuController()
    #else
    @State private var checkboxMenu: MenuRequest<TaskMarkerMenuRequest>?
    @State private var calloutMenu: MenuRequest<CalloutMenuRequest>?
    @State private var toggles = 0
    @State private var menuPresses = 0
    #endif

    var body: some View {
        #if os(macOS)
        NativeTextViewWrapper(
            text: $text,
            configuration: configuration,
            fontName: NSFont.systemFont(ofSize: 14).fontName,
            fontSize: 14,
            documentId: documentID,
            onLinkClick: onLinkClick,
            header: header,
            onSlashCommandChange: showSlashMenu,
            onSlashCommandKey: { key in
                switch key {
                case .moveUp: slashMenu.handle(.up)
                case .moveDown: slashMenu.handle(.down)
                case .confirm: slashMenu.handle(.confirm)
                case .confirmAndOpen, .cancel: false
                }
            },
            slashCommandProxy: slashCommand,
            onTaskMarkerMenu: showCheckboxMenu,
            onCalloutMenu: showCalloutMenu
        )
        .focusedValue(\.editor, slashCommand)
        .onDisappear {
            slashMenu.hide()
            checkboxMenu.hide()
            calloutMenu.hide()
        }
        #else
        NativeTextViewWrapper(
            text: $text,
            configuration: configuration,
            fontName: UIFont.systemFont(ofSize: 17).fontName,
            fontSize: 17,
            documentId: documentID,
            onLinkClick: onLinkClick,
            header: header,
            slashCommandProxy: slashCommand,
            onTaskMarkerMenu: {
                checkboxMenu = MenuRequest($0, anchor: localRect($0.anchorRect))
                menuPresses += 1
            },
            onCalloutMenu: {
                calloutMenu = MenuRequest($0, anchor: localRect($0.anchorRect))
                menuPresses += 1
            },
            onTaskCheckboxToggle: { _ in toggles += 1 },
            keyboardBar: AnyView(EditorKeyboardBar(theme: theme, proxy: slashCommand, closesWikiLinks: autocomplete.wikiLinks,
                                                   haptics: haptics))
        )
        .sensoryFeedback(.impact(weight: .light), trigger: toggles) { _, _ in haptics }
        .sensoryFeedback(.impact(weight: .medium), trigger: menuPresses) { _, _ in haptics }
        .popover(item: $checkboxMenu, attachmentAnchor: .rect(.rect(checkboxMenu?.anchor ?? .zero))) { menu in
            CheckboxMenu(current: menu.request.marker, theme: theme) { marker in
                checkboxMenu = nil
                menu.request.setMarker(marker)
                toggles += 1
            }
            .presentationCompactAdaptation(.popover)
        }
        .background {
            Color.clear
                .popover(item: $calloutMenu, attachmentAnchor: .rect(.rect(calloutMenu?.anchor ?? .zero))) { menu in
                    CalloutMenu(request: menu.request, theme: theme) { calloutMenu = nil }
                        .presentationCompactAdaptation(.popover)
                        .onDisappear { menu.request.close() }
                }
        }
        #endif
    }

    #if os(iOS)
    /// A window rect from the editor, in this view's coordinates, to anchor a popover.
    private func localRect(_ windowRect: CGRect) -> CGRect {
        guard let textView = slashCommand.textView else { return windowRect }
        return textView.convert(windowRect, from: nil).offsetBy(dx: -textView.bounds.minX, dy: -textView.bounds.minY)
    }
    #endif

    #if os(macOS)

    private func showCheckboxMenu(_ request: TaskMarkerMenuRequest) {
        checkboxMenu.show(
            current: request.marker, anchor: request.anchorRect, items: TaskCheckboxStyle.referenceMenu,
            theme: theme, pick: request.setMarker
        )
    }

    private func showCalloutMenu(_ request: CalloutMenuRequest) {
        calloutMenu.show(
            type: request.type, fold: request.fold, anchor: request.anchorRect, theme: theme,
            setType: { request.setType($0.rawValue) }, setFold: request.setFold, close: request.close
        )
    }

    private func showSlashMenu(_ state: SlashCommandState?) {
        guard let state else { return slashMenu.hide() }
        slashMenu.show(
            query: state.query, atLineStart: state.isAtLineStart, anchor: state.anchorRect, theme: theme,
            pick: { [slashCommand] command in
                let insertion = command.insertion(followsBlankLine: state.followsBlankLine)
                slashCommand.insert(insertion.text, selecting: insertion.selection)
            },
            dismiss: { [slashCommand] in slashCommand.dismiss() }
        )
    }
    #endif

    /// `due` behind a highlight.
    private var highlightFill: PlatformColor {
        theme.due.withAlphaComponent(theme.isDark ? 0.26 : 0.3)
    }

    private var configuration: MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration.default
        config.theme = MarkdownEditorTheme(
            bodyText: theme.fg,
            mutedText: theme.muted,
            disabledText: theme.muted.withAlphaComponent(0.6),
            headingMarker: theme.muted,
            link: theme.link,
            incompleteLink: theme.muted,
            findMatchHighlight: theme.due.withAlphaComponent(0.3),
            findCurrentMatchHighlight: theme.due.withAlphaComponent(0.6),
            latexLightModeText: theme.fg,
            latexDarkModeText: theme.fg,
            strikethroughColor: theme.muted,
            highlightColor: highlightFill,
            selectionBackground: theme.surface
        )
        let background = theme.bg
        var struck: Set<Character> = []
        var clicks: [Character: Character] = [:]
        for marker in TaskMarker.all {
            guard let state = Checkbox.State(marker: marker) else { continue }
            if state == .done || state == .cancelled { struck.insert(marker) }
            clicks[marker] = state.markerAfterClick
        }
        config.taskCheckbox = TaskCheckboxStyle(
            tints: Dictionary(uniqueKeysWithValues: TaskMarker.all.map { ($0, theme.checkboxTint($0)) }),
            struckMarkers: struck,
            clickTransitions: clicks,
            // A 16pt box on the 14pt body font (17pt high).
            sizeScale: 0.96,
            contentGap: 10,
            draw: { marker, rect, tint in
                guard let context = Self.currentContext else { return }
                InlineCheckbox.draw(marker, in: rect, tint: tint, background: background, context: context)
            }
        )
        // Inline code and highlights are bubbles with `strong` text.
        config.inlineCode.bubble = InlineBubble(fill: theme.code, ring: theme.border, text: theme.strong,
                                                horizontalPadding: 6, margin: 1)
        config.extensions = [HighlightBubble(bubble: InlineBubble(fill: highlightFill, text: theme.strong,
                                                                  horizontalPadding: 4, margin: -1))]
        let theme = self.theme
        config.callouts = CalloutStyle(
            tint: { theme.calloutTint(CalloutType(named: $0) ?? .note) },
            drawIcon: { type, rect, tint in
                guard let context = Self.currentContext else { return }
                CalloutIcon.draw(CalloutType(named: type) ?? .note, in: rect, tint: tint, context: context)
            },
            titleColor: theme.strong, bodyColor: theme.fg, foldColor: theme.muted, targetColor: theme.accent,
            fillOpacity: theme.isDark ? 0.14 : 0.09, ringOpacity: theme.isDark ? 0.3 : 0.24
        )
        config.services = MarkdownEditorServices(
            wikiLinks: TitleResolver(titles: linkTargets),
            syntaxHighlighter: CodeBlockStyle(background: theme.code)
        )
        config.lists.autoClosePairsEnabled = autocomplete.brackets
        config.lists.autoCloseFormattingEnabled = autocomplete.formatting
        config.lists.autoCloseWikiLinksEnabled = autocomplete.wikiLinks
        config.heightBehavior = fitsContent ? .fitsContent : .scrolls
        config.textInsets = TextInsets(horizontal: 16, vertical: 8)
        return config
    }

    /// The context the editor draws checkboxes and callout icons into.
    nonisolated private static var currentContext: CGContext? {
        #if os(macOS)
        NSGraphicsContext.current?.cgContext
        #else
        UIGraphicsGetCurrentContext()
        #endif
    }
}

#if os(macOS)
extension SlashCommandProxy: TextViewHolder {}
#endif

/// `==highlight==` as a bubble. It keeps the engine's highlight id, so the editor's Highlight command toggles it.
nonisolated private struct HighlightBubble: MarkdownExtension {
    let bubble: InlineBubble

    var id: String { HighlightExtension.identifier }
    var inline: InlineSyntax? { InlineSyntax(open: "==", close: "==") }
    func contentAttributes(theme: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
    func html(childrenHTML: String) -> String { "<mark>\(childrenHTML)</mark>" }
    func bubble(theme: MarkdownEditorTheme) -> InlineBubble? { bubble }
}

/// Resolves a link by its title, as `WikiLink` reads it, against the lowercased titles of the folder's files.
nonisolated struct TitleResolver: WikiLinkResolver {
    let titles: Set<String>

    func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? {
        guard let link = WikiLink(inner: displayName), titles.contains(link.title.lowercased()) else { return nil }
        return WikiLinkResolution(id: displayName, exists: true)
    }

    func fingerprint() -> AnyHashable { titles }
}

nonisolated private struct CodeBlockStyle: SyntaxHighlighter {
    let background: PlatformColor

    func codeFont(size: CGFloat) -> PlatformFont {
        PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func backgroundColor() -> PlatformColor { background }

    func highlight(code: String, language: String?) -> NSAttributedString? { nil }

    var appearanceDidChangeNotification: Notification.Name? { nil }
}

#if os(iOS)
/// A menu the editor asked for, with where to anchor it.
private struct MenuRequest<Request>: Identifiable {
    let id = UUID()
    let request: Request
    let anchor: CGRect

    init(_ request: Request, anchor: CGRect) {
        self.request = request
        self.anchor = anchor
    }
}

/// A press and hold on a task box: the common markers as boxes, then the reference set's other states by name.
private struct CheckboxMenu: View {
    let current: Character
    let theme: Theme
    let pick: (Character) -> Void
    @State private var showsAll = false

    private static let common: [Character] = [" ", "x", "/", "-", "!", "?"]
    private static let named: [Character] = [">", "<", "*", "I", "i", "\""]

    var body: some View {
        let items = TaskCheckboxStyle.referenceMenu
        let others = items.filter { !Self.common.contains($0.marker) && !Self.named.contains($0.marker) }
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(Self.common, id: \.self) { marker in
                        Button { pick(marker) } label: {
                            InlineCheckboxView(marker: marker, tint: theme.checkboxTint(marker), background: theme.bg)
                                .frame(width: 22, height: 22)
                                .frame(width: 40, height: 40)
                                .background(marker == current ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 10))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(items.first { $0.marker == marker }?.title ?? String(marker))
                        .accessibilityAddTraits(marker == current ? .isSelected : [])
                    }
                }
                .padding(12)
                Divider()
                ForEach(Self.named + (showsAll ? others.map(\.marker) : []), id: \.self) { marker in
                    row(marker, title: items.first { $0.marker == marker }?.title ?? String(marker))
                }
                if !showsAll {
                    Button { withAnimation(.snappy) { showsAll = true } } label: {
                        HStack {
                            Text("More States").foregroundStyle(theme.color(\.fg))
                            Spacer()
                            Text("\(others.count)").foregroundStyle(theme.color(\.muted))
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.color(\.muted))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 12)
        }
        .frame(width: 290)
        .frame(maxHeight: 460)
        .font(.system(size: 17))
    }

    private func row(_ marker: Character, title: String) -> some View {
        Button { pick(marker) } label: {
            HStack(spacing: 10) {
                Text(title).foregroundStyle(theme.color(\.fg))
                Spacer()
                if marker == current {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.color(\.accent))
                }
                Text(verbatim: "[\(marker)]").font(.system(size: 13, design: .monospaced)).foregroundStyle(theme.color(\.muted))
                InlineCheckboxView(marker: marker, tint: theme.checkboxTint(marker), background: theme.bg)
                    .frame(width: 18, height: 18)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A press and hold on a callout's title line: how it folds, then its type.
private struct CalloutMenu: View {
    let request: CalloutMenuRequest
    let theme: Theme
    let done: () -> Void

    var body: some View {
        let current = CalloutType(named: request.type)
        ScrollView {
            VStack(spacing: 0) {
                Picker("Fold", selection: Binding { request.fold.map(String.init) ?? "" } set: { sign in
                    request.setFold(sign.first)
                    done()
                }) {
                    Text("Fixed").tag("")
                    Text("Fold open").tag("+")
                    Text("Folded").tag("-")
                }
                .pickerStyle(.segmented)
                .padding(12)
                Divider()
                ForEach(CalloutType.allCases, id: \.self) { type in
                    Button {
                        request.setType(type.rawValue)
                        done()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.color(\.accent))
                                .opacity(type == current ? 1 : 0)
                            Text(type.title).foregroundStyle(theme.color(\.fg))
                            Spacer()
                            CalloutIconView(type: type, tint: theme.calloutTint(type)).frame(width: 18, height: 18)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(type == current ? .isSelected : [])
                }
            }
            .padding(.bottom, 12)
        }
        .frame(width: 270)
        .frame(maxHeight: 520)
        .font(.system(size: 17))
    }
}

/// Above the keyboard: subtask box, heading, bold, italic, code, wikilink, callout and indent buttons, and hide
/// keyboard. It's hosted outside SwiftUI's environment, so it takes the theme.
private struct EditorKeyboardBar: View {
    let theme: Theme
    let proxy: SlashCommandProxy
    /// Settings ▸ Editor's Wikilinks switch.
    let closesWikiLinks: Bool
    let haptics: Bool
    @State private var hides = 0

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    button("Subtask", "checkmark.square") { if let textView = proxy.textView { PhoneSubtask.perform(in: textView) } }
                    button("Heading", "textformat.size") { proxy.apply(.nextHeading) }
                    button("Bold", "bold") { proxy.apply(.bold) }
                    button("Italic", "italic") { proxy.apply(.italic) }
                    button("Code", "chevron.left.forwardslash.chevron.right") { proxy.apply(.inlineCode) }
                    button("Wikilink", "link") {
                        PhoneWikiLink.perform(with: proxy, closes: closesWikiLinks)
                    }
                    button("Callout", "text.bubble") { insert(SlashCommand.callout.insertion()) }
                    button("Outdent", "decrease.indent") { proxy.outdent() }
                    button("Indent", "increase.indent") { proxy.indent() }
                }
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.never)
            Divider().frame(height: 24)
            button("Hide Keyboard", "keyboard.chevron.compact.down") {
                hides += 1
                proxy.textView?.resignFirstResponder()
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 44)
        .glassEffect(in: .capsule)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .sensoryFeedback(.impact(weight: .light), trigger: hides) { _, _ in haptics }
    }

    private func button(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(theme.color(\.fg))
                .frame(width: 40, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    /// Inserts a format's text at the caret and selects its placeholder.
    private func insert(_ insertion: (text: String, selection: NSRange)) {
        guard let textView = proxy.textView else { return }
        let start = textView.selectedRange.location
        textView.insertText(insertion.text)
        textView.selectedRange = NSRange(location: start + insertion.selection.location, length: insertion.selection.length)
    }
}

/// The wikilink button: types `[[` as the keyboard does, so Autocomplete's switches apply; with Wikilinks on, a
/// selection becomes the link's text, and right before a `]]` the caret steps over it.
private enum PhoneWikiLink {
    static func perform(with proxy: SlashCommandProxy, closes: Bool) {
        guard let textView = proxy.textView else { return }
        let string = textView.text as NSString
        let selection = textView.selectedRange
        if closes, selection.length > 0 {
            proxy.type("[[\(string.substring(with: selection))]]")
        } else if closes, NSMaxRange(selection) + 2 <= string.length,
                  string.substring(with: NSRange(location: selection.location, length: 2)) == "]]" {
            textView.selectedRange = NSRange(location: selection.location + 2, length: 0)
        } else {
            proxy.type("[")
            proxy.type("[")
        }
    }
}

/// The subtask button: makes the caret's line a subtask, or completes (or reopens) it, as ⌘L does on the Mac.
private enum PhoneSubtask {
    static func perform(in textView: UITextView) {
        let string = textView.text as NSString
        let caret = textView.selectedRange.location
        var start = 0, end = 0, contentsEnd = 0
        string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        let line = string.substring(with: NSRange(location: start, length: contentsEnd - start))
        switch SubtaskLine.edit(for: line[...]) {
        case let .convert(offset, inserted):
            let location = start + offset
            textView.selectedRange = NSRange(location: location, length: 0)
            textView.insertText(inserted)
            let length = (inserted as NSString).length
            textView.selectedRange = NSRange(location: caret >= location ? caret + length : caret, length: 0)
        case let .setMarker(offset, marker):
            textView.selectedRange = NSRange(location: start + offset, length: 1)
            textView.insertText(String(marker))
            textView.selectedRange = NSRange(location: caret, length: 0)
        case .none:
            break
        }
    }
}
#endif
