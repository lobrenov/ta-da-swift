// The only file that imports TaDaMarkdown.
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import TaDaMarkdown
import TaDaCore
import ImageIO
import UniformTypeIdentifiers

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
    /// What `[[`, `![[` and `#` list and embeds draw; without it, typing them opens no menu.
    var links: LinkMenuSource? = nil
    /// Saves a pasted or dropped image and returns its `![[ ]]`; without it, images paste as the system does.
    var embedImage: ((AppModel.PastedImage) -> String?)? = nil
    /// Copies, renames, reveals and deletes the images embeds draw, from the embed menu (`EmbedMenu.swift`);
    /// without it, images have no menu.
    var imageActions: AppModel? = nil
    /// Receives the link target (`[[Target|alias]]` reports `Target`).
    var onLinkClick: (String) -> Void = { _ in }
    /// Receives a clicked `#tag`, as written, without `#`; without it, tags draw as bubbles but don't open.
    var onTagClick: ((String) -> Void)? = nil

    @State private var slashCommand = SlashCommandProxy()
    #if os(macOS)
    @State private var slashMenu = SlashMenuController()
    @State private var checkboxMenu = CheckboxMenuController()
    @State private var calloutMenu = CalloutMenuController()
    @State private var rightClickMenu = RightClickMenuController()
    @State private var linkMenu = LinkMenuController()
    @State private var tagMenu = TagMenuController()
    #else
    @State private var linkSearch = LinkMenuSearch()
    /// The open `[[` or `![[` query's choices, and the one ↵ picks.
    @State private var linkChoices: [LinkChoice] = []
    @State private var linkHighlight = 0
    /// The open `#` query's choices (empty: "New tag"), and the one ↵ picks.
    @State private var tagChoices: [TagNode]?
    @State private var tagHighlight = 0
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
            onPasteImage: embedImage.map { embed in
                { pasteboard in
                    if let url = PasteboardImageReader.imageFileURL(from: pasteboard),
                       Vault.imageExtensions.contains(url.pathExtension.lowercased()) {
                        return embed(.file(url))
                    }
                    // Rich text can carry a picture of itself; it pastes as text. An image file of another type pastes as PNG.
                    guard pasteboard.string(forType: .string) == nil,
                          let data = PasteboardImageReader.imageData(from: pasteboard) else { return nil }
                    return embed(.data(data, extension: "png"))
                }
            },
            onLinkClick: onLinkClick,
            header: header,
            onSlashCommandChange: showQueryMenu,
            onSlashCommandKey: { key in
                switch key {
                case .moveUp: slashMenu.handle(.up) || linkMenu.handle(.up) || tagMenu.handle(.up)
                case .moveDown: slashMenu.handle(.down) || linkMenu.handle(.down) || tagMenu.handle(.down)
                case .confirm: slashMenu.handle(.confirm) || linkMenu.handle(.confirm) || tagMenu.handle(.confirm)
                case .confirmAndOpen, .cancel: false
                }
            },
            slashCommandProxy: slashCommand,
            onTaskMarkerMenu: showCheckboxMenu,
            onCalloutMenu: showCalloutMenu,
            onImageEmbed: imageActions.map { model in { request in handleImage(request, model: model) } },
            onTagClick: onTagClick,
            onRightClickMenu: showRightClickMenu
        )
        .focusedValue(\.editor, slashCommand)
        .onAppear { slashCommand.triggers = triggers }
        .onChange(of: autocomplete.tags) { slashCommand.triggers = triggers }
        .onDisappear {
            slashMenu.hide()
            linkMenu.hide()
            tagMenu.hide()
            checkboxMenu.hide()
            calloutMenu.hide()
            rightClickMenu.hide()
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
            onSlashCommandChange: showLinkChoices,
            onSlashCommandKey: handleLinkKey,
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
            keyboardBar: AnyView(VStack(spacing: 0) {
                if !linkChoices.isEmpty {
                    PhoneLinkList(choices: linkChoices, highlight: linkHighlight, search: linkSearch, theme: theme, pick: insertLink)
                }
                if let tagChoices {
                    PhoneTagList(choices: tagChoices, highlight: tagHighlight, theme: theme, pick: insertTag)
                }
                EditorKeyboardBar(theme: theme, proxy: slashCommand, closesWikiLinks: autocomplete.wikiLinks, haptics: haptics)
            }),
            onPasteImage: embedImage.map { embed in
                { pasteboard in
                    if let url = pasteboard.urls?.first(where: { $0.isFileURL && Vault.imageExtensions.contains($0.pathExtension.lowercased()) }) {
                        return embed(.file(url))
                    }
                    let types: [(UTType, String)] = [(.png, "png"), (.jpeg, "jpg"), (.heic, "heic"), (.gif, "gif"),
                                                     (.webP, "webp"), (.tiff, "tiff")]
                    for (type, ext) in types {
                        if let data = pasteboard.data(forPasteboardType: type.identifier) { return embed(.data(data, extension: ext)) }
                    }
                    return pasteboard.image?.pngData().flatMap { embed(.data($0, extension: "png")) }
                }
            },
            imageEmbedMenu: imageActions.map { model in
                { request in
                    model.attachmentPath(forEmbed: request.name).map { path in
                        menuPresses += 1
                        return EmbedMenu.menu(for: path, model: model, cut: { request.remove("Cut Image") },
                                              editMarkdown: request.revealSource)
                    }
                }
            },
            onTagClick: onTagClick
        )
        .onAppear { slashCommand.triggers = triggers }
        .onChange(of: autocomplete.tags) { slashCommand.triggers = triggers }
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

    /// The queries typing opens: `/` on the Mac, and with `links`, `[[`, `![[` and (by Autocomplete) `#`.
    private var triggers: Set<SlashCommandState.Trigger> {
        #if os(macOS)
        var triggers: Set<SlashCommandState.Trigger> = [.slash]
        #else
        var triggers: Set<SlashCommandState.Trigger> = []
        #endif
        if links != nil { triggers.formUnion(autocomplete.tags ? [.link, .embed, .tag] : [.link, .embed]) }
        return triggers
    }

    /// Replaces the `[[` or `![[` query with the choice's link or embed and puts the caret after it.
    private func insertLink(_ choice: LinkChoice) {
        let text = choice.markdown
        slashCommand.insert(text, selecting: NSRange(location: (text as NSString).length, length: 0))
    }

    /// Replaces the `#` query with the tag's full path and a space, and puts the caret after it.
    private func insertTag(_ node: TagNode) {
        let text = node.insertion
        slashCommand.insert(text, selecting: NSRange(location: (text as NSString).length, length: 0))
    }

    #if os(iOS)
    /// Lists the open `[[`, `![[` or `#` query's choices above the keyboard bar.
    private func showLinkChoices(_ state: SlashCommandState?) {
        if let state, let links, state.trigger == .tag {
            let choices = links.tagSuggestions(state.query)
            if choices != tagChoices { tagHighlight = 0 }
            tagChoices = choices
            linkChoices = []
            return
        }
        tagChoices = nil
        guard let state, let links, state.trigger != .slash else {
            linkChoices = []
            return
        }
        linkSearch.source = links
        let choices = linkSearch.choices(state.trigger == .link ? .link : .embed, query: state.query).choices
        if choices != linkChoices { linkHighlight = 0 }
        linkChoices = choices
    }

    /// A hardware keyboard's ↑/↓ move through the choices and ↵ picks one.
    private func handleLinkKey(_ key: InlinePreviewKey) -> Bool {
        if let tagChoices, !tagChoices.isEmpty {
            switch key {
            case .moveUp: tagHighlight = (tagHighlight + tagChoices.count - 1) % tagChoices.count
            case .moveDown: tagHighlight = (tagHighlight + 1) % tagChoices.count
            case .confirm, .confirmAndOpen: insertTag(tagChoices[min(tagHighlight, tagChoices.count - 1)])
            case .cancel: return false
            }
            return true
        }
        guard !linkChoices.isEmpty else { return false }
        switch key {
        case .moveUp: linkHighlight = (linkHighlight + linkChoices.count - 1) % linkChoices.count
        case .moveDown: linkHighlight = (linkHighlight + 1) % linkChoices.count
        case .confirm, .confirmAndOpen: insertLink(linkChoices[min(linkHighlight, linkChoices.count - 1)])
        case .cancel: return false
        }
        return true
    }

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

    private func showRightClickMenu(_ request: RightClickMenuRequest) {
        rightClickMenu.show(
            request.sections.map { section in
                section.map { RightClickMenuEntry(title: $0.title, systemImage: $0.symbolName, shortcut: $0.shortcut,
                                                 isChecked: $0.isChecked, isDestructive: $0.isDestructive, action: $0.action) }
            },
            anchor: request.anchorRect, theme: theme, close: request.close
        )
    }

    /// A right-click on an image opens the embed menu; ⌘C, ⌘X and ⌘⌫ on a selected one copy, cut or delete it.
    private func handleImage(_ request: ImageEmbedRequest, model: AppModel) {
        guard let path = model.attachmentPath(forEmbed: request.name) else { return request.close() }
        switch request.action {
        case .copy:
            model.copyImage(path)
        case .cut:
            model.copyImage(path) { request.remove("Cut Image") }
        case .delete:
            model.imageDialog = .delete(path)
        case .menu:
            guard let window = NSApp.keyWindow else { return request.close() }
            FileMenu.shared.show(FileMenuAction.embedActions(for: path, model: model, cut: { request.remove("Cut Image") }),
                                 at: request.anchorRect.origin, in: window, theme: theme, onClose: request.close)
        }
    }

    private func showQueryMenu(_ state: SlashCommandState?) {
        switch state?.trigger {
        case nil:
            slashMenu.hide()
            linkMenu.hide()
            tagMenu.hide()
        case .slash:
            linkMenu.hide()
            tagMenu.hide()
            showSlashMenu(state!)
        case .link, .embed:
            slashMenu.hide()
            tagMenu.hide()
            showLinkMenu(state!)
        case .tag:
            slashMenu.hide()
            linkMenu.hide()
            showTagMenu(state!)
        }
    }

    private func showTagMenu(_ state: SlashCommandState) {
        guard let links else { return }
        tagMenu.show(links.tagSuggestions(state.query), anchor: state.anchorRect, theme: theme, pick: insertTag,
                     dismiss: { [slashCommand] in slashCommand.dismiss() })
    }

    private func showLinkMenu(_ state: SlashCommandState) {
        guard let links else { return }
        linkMenu.search.source = links
        linkMenu.show(
            state.trigger == .link ? .link : .embed, query: state.query, anchor: state.anchorRect, theme: theme,
            pick: insertLink, dismiss: { [slashCommand] in slashCommand.dismiss() }
        )
    }

    private func showSlashMenu(_ state: SlashCommandState) {
        slashMenu.show(
            query: state.query, atLineStart: state.isAtLineStart, inTableCell: state.inTableCell,
            anchor: state.anchorRect, theme: theme,
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
        // Tags are bubbles in `accent`: fill 14% (10% on light schemes), ring 32% (28%).
        config.tags = TagStyle(bubble: InlineBubble(
            fill: theme.accent.withAlphaComponent(theme.isDark ? 0.14 : 0.1),
            ring: theme.accent.withAlphaComponent(theme.isDark ? 0.32 : 0.28),
            text: theme.accent, horizontalPadding: 6, margin: 1))
        config.extensions = [HighlightBubble(bubble: InlineBubble(fill: highlightFill, text: theme.strong,
                                                                  horizontalPadding: 4, margin: -1)),
                             StrikethroughExtension()]
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
            images: AttachmentImages(root: links?.vault?.root, paths: links?.attachments ?? []),
            syntaxHighlighter: CodeBlockStyle(background: theme.code)
        )
        // Images stay drawn as the caret passes; a missing one is muted and dashed, as an unresolved link.
        config.imageEmbed.revealsSourceAtCaret = false
        config.imageEmbed.missingText = theme.muted.withAlphaComponent(0.6)
        #if os(macOS)
        config.imageEmbed.cornerRadius = 6
        config.liveTables = true
        config.tableAccent = theme.accent
        config.imageEmbed.selectionRing = theme.accent
        config.imageEmbed.sourceButton = .init(fill: theme.isDark ? theme.side : theme.bg, hoverFill: theme.surface,
                                               ring: theme.surface, tint: theme.fg, hoverTint: theme.accent)
        #else
        config.imageEmbed.cornerRadius = 8
        #endif
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

extension SlashCommandProxy: InlineFormatting {
    /// Formats only while the editor (or its table cell) has the keyboard in the key window, not behind Quick Entry or a menu.
    func apply(_ format: InlineFormat) {
        guard let textView, let window = textView.window, window.isKeyWindow, window.firstResponder === textView else { return }
        switch format {
        case .bold: apply(MarkdownFormat.bold)
        case .italic: apply(MarkdownFormat.italic)
        case .highlight: apply(MarkdownFormat.highlight)
        case .strikethrough: apply(MarkdownFormat.strikethrough)
        }
    }
}
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

/// Draws `![[name.png]]` from the folder's images, found as `Vault.attachmentPath(for:in:)` finds them. An image keeps
/// its pixel size in points, so the editor fits a large one to its width.
nonisolated struct AttachmentImages: EmbeddedImageProvider {
    let root: URL?
    let paths: [String]

    func image(for request: EmbeddedImageRequest) -> PlatformImage? {
        guard let root, let embed = WikiLink(inner: request.name),
              let path = Vault.attachmentPath(for: embed, in: paths) else { return nil }
        return Self.load(Vault(root: root).url(for: path))
    }

    func fingerprint() -> AnyHashable { [root?.path ?? ""] + paths }

    /// Decodes at most 2048 pixels on the long side.
    static func load(_ url: URL) -> PlatformImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2048,
              ] as CFDictionary) else { return nil }
        // EXIF orientations 5 to 8 turn the image a quarter.
        let turned = ((properties[kCGImagePropertyOrientation] as? Int) ?? 1) >= 5
        let width = turned ? pixelHeight : pixelWidth
        #if os(macOS)
        return NSImage(cgImage: image, size: CGSize(width: width, height: turned ? pixelWidth : pixelHeight))
        #else
        return UIImage(cgImage: image, scale: CGFloat(image.width) / width, orientation: .up)
        #endif
    }
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
        .frame(width: 294)
        // The popover lays its content out across the bubble and its arrow; the menu keeps to the bubble.
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: 520)
        .font(.system(size: 17))
    }
}

/// Above the keyboard: subtask box, `#`, bold, italic, code, wikilink, callout and indent buttons, and hide
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
                    Button { proxy.type("#") } label: {
                        Text(verbatim: "#")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.color(\.accent))
                            .frame(width: 40, height: 36)
                            .background(theme.tagFill(), in: .capsule)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Insert #")
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

/// The `[[` or `![[` query's choices, above the keyboard bar: a tap picks one.
private struct PhoneLinkList: View {
    let choices: [LinkChoice]
    let highlight: Int
    let search: LinkMenuSearch
    let theme: Theme
    let pick: (LinkChoice) -> Void

    private static let rowHeight: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { offset, choice in
                    Button { pick(choice) } label: {
                        HStack(spacing: 12) {
                            LinkChoiceIcon(icon: choice.icon, search: search, theme: theme, size: 18)
                                .frame(width: 28, height: 28)
                            Text(choice.title)
                                .foregroundStyle(theme.color(offset == highlight ? \.strong : \.fg))
                                .lineLimit(1)
                                .layoutPriority(1)
                            Spacer(minLength: 8)
                            Text(choice.hint)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.color(\.muted))
                                .lineLimit(1)
                                .frame(maxWidth: 120, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: Self.rowHeight)
                        .background(offset == highlight ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 16))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(choice.hint)
                }
            }
            .padding(4)
        }
        .scrollIndicators(.never)
        .frame(height: min(CGFloat(choices.count) * Self.rowHeight + 8, 162))
        .font(.system(size: 17))
        .glassEffect(in: .rect(cornerRadius: 20))
        .padding(.horizontal, 8)
        .padding(.top, 4)
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
