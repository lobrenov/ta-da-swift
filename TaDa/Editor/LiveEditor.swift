// The only file that imports MarkdownEngine.
import SwiftUI
import AppKit
import MarkdownEngine
import TaDaCore

struct LiveEditor: View {
    @Binding var text: String
    let theme: Theme
    let documentID: String
    /// Titles that links can resolve to, matched case-insensitively.
    var linkTargets: Set<String> = []
    var fitsContent = false
    var header: AnyView? = nil
    /// Receives the link target (`[[Target|alias]]` reports `Target`).
    var onLinkClick: (String) -> Void = { _ in }

    @State private var slashMenu = SlashMenuController()
    @State private var slashCommand = SlashCommandProxy()
    @State private var checkboxMenu = CheckboxMenuController()

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
            onTaskMarkerMenu: showCheckboxMenu
        )
        .onDisappear {
            slashMenu.hide()
            checkboxMenu.hide()
        }
    }

    private func showCheckboxMenu(_ request: TaskMarkerMenuRequest) {
        checkboxMenu.show(
            current: request.marker, anchor: request.anchorRect, items: TaskCheckboxStyle.referenceMenu,
            theme: theme, pick: request.setMarker
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
            highlightColor: theme.due.withAlphaComponent(0.3),
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
        config.services = MarkdownEditorServices(
            wikiLinks: TitleResolver(titles: linkTargets),
            syntaxHighlighter: CodeBlockStyle(background: theme.code)
        )
        config.heightBehavior = fitsContent ? .fitsContent : .scrolls
        config.textInsets = TextInsets(horizontal: 16, vertical: 8)
        return config
    }
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
