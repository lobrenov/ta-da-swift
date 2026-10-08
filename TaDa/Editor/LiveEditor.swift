// The only file that imports TaDaMarkdown.
import SwiftUI
import AppKit
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
    var header: AnyView? = nil
    /// Receives the link target (`[[Target|alias]]` reports `Target`).
    var onLinkClick: (String) -> Void = { _ in }

    @State private var slashMenu = SlashMenuController()
    @State private var slashCommand = SlashCommandProxy()
    @State private var checkboxMenu = CheckboxMenuController()
    @State private var calloutMenu = CalloutMenuController()

    var body: some View {
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
    }

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

    /// `due` behind a highlight.
    private var highlightFill: NSColor {
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
                guard let context = NSGraphicsContext.current?.cgContext else { return }
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
                guard let context = NSGraphicsContext.current?.cgContext else { return }
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
}

extension SlashCommandProxy: TextViewHolder {}

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
    let background: NSColor

    func codeFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func backgroundColor() -> NSColor { background }

    func highlight(code: String, language: String?) -> NSAttributedString? { nil }

    var appearanceDidChangeNotification: Notification.Name? { nil }
}
