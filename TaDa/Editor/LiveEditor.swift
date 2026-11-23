// The only file that imports MarkdownEngine.
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
import Combine
#endif
import MarkdownEngine
import MarkdownEngineSyntax
import TaDaCore
import ImageIO
import UniformTypeIdentifiers

/// Scrolls an editor's line to the top of the page; the editor sets `toLine` while it's shown.
final class EditorScroll {
    var toLine: (Int) -> Void = { _ in }
}

struct LiveEditor: View {
    @Binding var text: String
    let theme: Theme
    let documentID: String
    /// Titles that links can resolve to, matched case-insensitively.
    var linkTargets: Set<String> = []
    /// The status of the task each lowercased title resolves to (`TitleResolver`).
    var linkStatuses: [String: Status] = [:]
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
    /// Extracts subtasks to tasks from the checkbox menu (`ExtractTask.swift`, Mac); without it, the menu has no Extract to Task row.
    var taskExtraction: AppModel? = nil
    /// Draws and edits a subtask's `>YYYY-MM-DD` due date and `@[[Title]]` parent (`TaskAttributeMenus.swift`); without it, they stay text.
    var taskAttributes: AppModel? = nil
    /// Gives the editor the keyboard, caret at the start, once its text view is in a window; then calls `onTookFocus`.
    var takesFocus = false
    var onTookFocus: () -> Void = {}
    /// Receives the link target (`[[Target|alias]]` reports `Target`).
    var onLinkClick: (String) -> Void = { _ in }
    /// Receives a clicked `#tag`, as written, without `#`; without it, tags draw as bubbles but don't open.
    var onTagClick: ((String) -> Void)? = nil
    /// The 0-based first and last visible lines, as the page scrolls.
    var onVisibleLines: ((ClosedRange<Int>) -> Void)? = nil
    /// Gets a way to scroll a line to the top.
    var scroll: EditorScroll? = nil
    /// Whether a point in window coordinates is over something drawn on the editor that owns the cursor, so it shows the arrow.
    var isCursorExcluded: ((CGPoint) -> Bool)? = nil

    @State private var slashCommand = SlashCommandProxy()
    /// Whether the editor has the keyboard; setting it gives or drops it.
    @State private var focused = false
    #if os(macOS)
    @State private var slashMenu = SlashMenuController()
    @State private var checkboxMenu = CheckboxMenuController()
    @State private var calloutMenu = CalloutMenuController()
    @State private var rightClickMenu = RightClickMenuController()
    @State private var textMenu = TextMenuController()
    @State private var linkMenu = LinkMenuController()
    @State private var addLinkMenu = AddLinkMenuController()
    @State private var tagMenu = TagMenuController()
    @State private var dateMenu = DateMenuController()
    @State private var parentMenu = ParentMenuController(takesKeys: false)
    @State private var parentChipMenu = ParentMenuController(takesKeys: true)
    @State private var calendar = CalendarPicker()
    #else
    /// The open `/` query's choices, the one ↵ picks, and the query's state, which a pick inserts against.
    @State private var slashChoices: [SlashCommand] = []
    @State private var slashHighlight = 0
    @State private var slashState: SlashCommandState?
    @State private var linkSearch = LinkMenuSearch()
    /// The open `[[` or `![[` query's choices, and the one ↵ picks.
    @State private var linkChoices: [LinkChoice] = []
    @State private var linkHighlight = 0
    /// The open `#` query's choices (empty: "New tag"), and the one ↵ picks.
    @State private var tagChoices: [TagNode]?
    @State private var tagHighlight = 0
    /// The open `>` query's choices, and the one ↵ picks.
    @State private var dateChoices: [DateChoice] = []
    @State private var dateHighlight: Int?
    /// The open `@` query's choices, and the one ↵ picks.
    @State private var parentChoices: [ParentChoice] = []
    @State private var parentHighlight: Int?
    /// The open `>` or `@` query, which a pick replaces.
    @State private var attributeState: SlashCommandState?
    @State private var attributeMenu: MenuRequest<TaskAttributeClick>?
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
            isFocused: $focused,
            onPasteImage: embedImage.map { embed in
                { pasteboard in
                    if let url = PasteboardImageReader.imageFileURL(from: pasteboard),
                       Vault.imageExtensions.contains(url.pathExtension.lowercased()) {
                        return embed(.file(url))
                    }
                    let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
                    if let url = Self.pastedFile(in: urls) { return embed(.file(url)) }
                    // Rich text can carry a picture of itself; it pastes as text. An image file of another type pastes as PNG.
                    guard pasteboard.string(forType: .string) == nil,
                          let data = PasteboardImageReader.imageData(from: pasteboard) else { return nil }
                    return embed(.data(data, extension: "png"))
                }
            },
            onLinkClick: onLinkClick,
            // Keys for any open picker come here (a query, upstream's `[[…]]` preview); each menu ignores them unless it's open.
            onInlinePreviewKey: handleMenuKey,
            header: header,
            isCursorExcluded: isCursorExcluded,
            onSlashCommandChange: showQueryMenu,
            slashCommandProxy: slashCommand,
            onTaskMarkerMenu: showCheckboxMenu,
            onCalloutMenu: showCalloutMenu,
            onImageEmbed: imageActions.map { model in { request in handleImage(request, model: model) } },
            onTagClick: onTagClick,
            onTaskAttributeClick: attributeClick,
            onRightClickMenu: showRightClickMenu,
            onTextMenu: showTextMenu,
            onVisibleLines: onVisibleLines
        )
        .focusedValue(\.editor, slashCommand)
        .onAppear {
            slashCommand.triggers = triggers
            scroll?.toLine = { [slashCommand] in slashCommand.scroll(toLine: $0) }
        }
        .onChange(of: takesFocus, initial: true) {
            guard takesFocus else { return }
            if focused { tookFocus() } else { focused = true }
        }
        .onChange(of: focused) {
            if focused, takesFocus { tookFocus() }
        }
        .onChange(of: autocomplete.tags) { slashCommand.triggers = triggers }
        .onDisappear {
            slashMenu.hide()
            linkMenu.hide()
            tagMenu.hide()
            dateMenu.hide()
            parentMenu.hide()
            parentChipMenu.hide()
            calendar.hide()
            checkboxMenu.hide()
            calloutMenu.hide()
            rightClickMenu.hide()
            textMenu.hide()
            addLinkMenu.hide()
        }
        #else
        NativeTextViewWrapper(
            text: $text,
            configuration: configuration,
            fontName: UIFont.systemFont(ofSize: 17).fontName,
            fontSize: 17,
            documentId: documentID,
            isFocused: $focused,
            onLinkClick: onLinkClick,
            header: header,
            onSlashCommandChange: showLinkChoices,
            onInlinePreviewKey: handleLinkKey,
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
                if slashState != nil {
                    PhoneSlashList(choices: slashChoices, highlight: slashHighlight, theme: theme, pick: insertSlashCommand)
                }
                if !linkChoices.isEmpty {
                    PhoneLinkList(choices: linkChoices, highlight: linkHighlight, search: linkSearch, theme: theme, pick: insertLink)
                }
                if let tagChoices {
                    PhoneTagList(choices: tagChoices, highlight: tagHighlight, theme: theme, pick: insertTag)
                }
                if !dateChoices.isEmpty {
                    PhoneDateList(choices: dateChoices, highlight: dateHighlight, theme: theme, pick: insertDate)
                }
                if !parentChoices.isEmpty {
                    PhoneParentList(choices: parentChoices, highlight: parentHighlight, theme: theme) { insertParent($0, in: attributeState) }
                }
                EditorKeyboardBar(theme: theme, proxy: slashCommand, closesWikiLinks: autocomplete.wikiLinks, haptics: haptics,
                                  hasAttributeKeys: taskAttributes != nil, hideKeyboard: { focused = false })
            }),
            onPasteImage: embedImage.map { embed in
                { pasteboard in
                    if let url = pasteboard.urls?.first(where: { $0.isFileURL && Vault.imageExtensions.contains($0.pathExtension.lowercased()) }) {
                        return embed(.file(url))
                    }
                    if let url = Self.pastedFile(in: pasteboard.urls ?? []) {
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
                        return EmbedMenu.menu(for: path, model: model, cut: { request.remove("Cut") },
                                              editMarkdown: request.revealSource)
                    }
                }
            },
            onTagClick: onTagClick,
            onTaskAttributeClick: taskAttributes == nil ? nil : { click in
                attributeMenu = MenuRequest(click, anchor: localRect(click.anchorRect))
                menuPresses += 1
            },
            onVisibleLines: onVisibleLines
        )
        .onAppear {
            slashCommand.triggers = triggers
            scroll?.toLine = { [slashCommand] in slashCommand.scroll(toLine: $0) }
        }
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
                .popover(item: $attributeMenu, attachmentAnchor: .rect(.rect(attributeMenu?.anchor ?? .zero))) { menu in
                    attributePopover(menu.request)
                        .presentationCompactAdaptation(.popover)
                }
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

    #if os(macOS)
    /// The caret to the body's start, then `onTookFocus`.
    private func tookFocus() {
        slashCommand.textView?.setSelectedRange(NSRange(location: 0, length: 0))
        onTookFocus()
    }
    #endif

    /// The queries typing opens: `/`; with `links`, `[[`, `![[` and (by Autocomplete) `#`; with `taskAttributes`, `>` and `@`.
    private var triggers: Set<SlashCommandState.Trigger> {
        var triggers: Set<SlashCommandState.Trigger> = [.slash]
        if links != nil { triggers.formUnion(autocomplete.tags ? [.link, .embed, .tag] : [.link, .embed]) }
        if taskAttributes != nil { triggers.formUnion([.date, .parent]) }
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

    #if os(macOS)
    private var attributeClick: ((TaskAttributeClick) -> Void)? {
        taskAttributes == nil ? nil : { showAttributeMenu($0) }
    }
    #endif

    /// Replaces the `>` query with the day's `>YYYY-MM-DD` and a space, and puts the caret after it.
    private func insertDate(_ choice: DateChoice) {
        guard let text = choice.markdown else { return }
        slashCommand.insert(text, selecting: NSRange(location: (text as NSString).length, length: 0))
    }

    /// Replaces the `@` query with the parent's `@[[Title]]` and a space, and puts the caret after it. New project makes the
    /// project first and links the title it has; the link goes in over the query as it was at the pick, if the text there is
    /// unchanged.
    private func insertParent(_ choice: ParentChoice, in state: SlashCommandState?) {
        let text = choice.markdown
        guard choice.kind == .new, let model = taskAttributes else {
            return slashCommand.insert(text, selecting: NSRange(location: (text as NSString).length, length: 0))
        }
        let replace = state.flatMap(replacingQuery)
        slashCommand.dismiss()
        Task {
            guard let project = await model.newProject(named: choice.title, linking: []) else { return }
            _ = replace?("@[[\(project.title)]] ")
        }
    }

    /// A way to replace `state`'s query as it is now with text, once, if the text there is still the same; the caret goes after it.
    private func replacingQuery(_ state: SlashCommandState) -> ((String) -> Bool)? {
        guard let textView = slashCommand.textView else { return nil }
        func string() -> NSString {
            #if os(macOS)
            textView.string as NSString
            #else
            textView.text as NSString
            #endif
        }
        guard NSMaxRange(state.range) <= string().length else { return nil }
        var range = state.range
        let source = string().substring(with: range)
        // The `]]` an auto-pair closed `@[[` with goes too.
        var closers = source.hasPrefix("@[[") ? 2 : (source.hasPrefix("@[") ? 1 : 0)
        while closers > 0, NSMaxRange(range) < string().length, string().character(at: NSMaxRange(range)) == 0x5D {
            range.length += 1
            closers -= 1
        }
        let expected = string().substring(with: range)
        return { text in
            guard NSMaxRange(range) <= string().length, string().substring(with: range) == expected else { return false }
            #if os(macOS)
            textView.insertText(text, replacementRange: range)
            #else
            textView.selectedRange = range
            textView.insertText(text)
            #endif
            return true
        }
    }

    /// Deletes a clicked attribute, with a space beside it.
    private func removeAttribute(_ click: TaskAttributeClick) {
        guard let textView = slashCommand.textView else { return }
        #if os(macOS)
        guard let range = TaskAttributeText.removalRange(of: click.source, isDue: click.kind == .due, at: click.range, in: textView.string) else { return }
        textView.insertText("", replacementRange: range)
        #else
        guard let range = TaskAttributeText.removalRange(of: click.source, isDue: click.kind == .due, at: click.range, in: textView.text) else { return }
        textView.selectedRange = range
        textView.insertText("")
        #endif
    }

    /// The chips' look: a date as a task row labels it, accent or `deadline` when overdue; a parent as its icon (a project's
    /// ring in `accent`, an area's cube in `doing`) and title in `link`, or its title struck and muted when it isn't a project or area.
    nonisolated static func taskAttributeStyle(theme: Theme, index: VaultIndex, today: LocalDate, generation: Int = 0) -> TaskAttributeStyle {
        TaskAttributeStyle(
            due: { text in
                guard let date = LocalDate(text) else { return TaskAttributeChip(label: text, tint: theme.muted) }
                return TaskAttributeChip(label: MainActor.assumeIsolated { date.rowLabel(today: today) },
                                         tint: date < today ? theme.deadline : theme.accent)
            },
            parent: { title, _ in
                guard let place = index.parentItem(titled: WikiLink(inner: title)?.title ?? title) else {
                    return TaskAttributeChip(label: title, tint: theme.muted, strikethrough: true)
                }
                let icon: @Sendable (CGRect, PlatformColor) -> Void
                if place.properties.kind == .area {
                    let tint = theme.doing
                    icon = { rect, _ in
                        guard let context = Self.currentContext else { return }
                        TaskAttributeIcons.cube(in: rect, tint: tint, context: context)
                    }
                } else {
                    let tint = theme.accent, fraction = index.progress(of: place).fraction
                    icon = { rect, _ in
                        guard let context = Self.currentContext else { return }
                        TaskAttributeIcons.ring(fraction: fraction, in: rect, tint: tint, context: context)
                    }
                }
                return TaskAttributeChip(label: place.title, tint: theme.link, drawIcon: icon)
            },
            fingerprint: { [generation, today] as [AnyHashable] }
        )
    }

    #if os(iOS)
    /// The content of the popover a tap on a drawn date or parent opens.
    @ViewBuilder private func attributePopover(_ click: TaskAttributeClick) -> some View {
        if let model = taskAttributes {
            switch click.kind {
            case .due:
                PhoneDatePopover(current: LocalDate(String(click.source.dropFirst())), today: model.today, theme: theme, pick: { date in
                    attributeMenu = nil
                    click.replace(">\(date)")
                }, remove: {
                    attributeMenu = nil
                    removeAttribute(click)
                })
            case .parent:
                PhoneParentPopover(choices: ParentChoice.choices(index: model.index, query: "") + [.remove], theme: theme) { choice in
                    attributeMenu = nil
                    if choice.kind == .remove { removeAttribute(click) } else { click.replace(choice.token) }
                }
            }
        }
    }

    /// Replaces the `/query` with the command's markdown and selects its placeholder.
    private func insertSlashCommand(_ command: SlashCommand) {
        let insertion = command.insertion(followsBlankLine: slashState?.followsBlankLine ?? true)
        slashCommand.insert(insertion.text, selecting: insertion.selection)
    }

    /// Lists the open `/`, `[[`, `![[`, `#`, `>` or `@` query's choices above the keyboard bar.
    private func showLinkChoices(_ state: SlashCommandState?) {
        if let state, state.trigger == .slash {
            let choices = SlashCommand.matching(state.query, atLineStart: state.isAtLineStart)
                .filter { !state.inTableCell || ($0 != .table && $0 != .image) }
            if choices != slashChoices { slashHighlight = 0 }
            slashChoices = choices
            slashState = state
            tagChoices = nil
            linkChoices = []
            dateChoices = []
            parentChoices = []
            return
        }
        if let state, let model = taskAttributes, state.trigger == .date || state.trigger == .parent {
            slashChoices = []
            slashState = nil
            tagChoices = nil
            linkChoices = []
            attributeState = state
            if state.trigger == .date {
                let choices = DateChoice.choices(query: state.query, today: model.today, firstWeekday: Calendar.current.firstWeekday,
                                                 order: .system, includesPick: false)
                if choices != dateChoices { dateHighlight = DateChoice.highlight(in: choices) }
                dateChoices = choices
                parentChoices = []
            } else {
                let choices = ParentChoice.choices(index: model.index, query: state.query)
                if choices != parentChoices { parentHighlight = ParentChoice.highlight(in: choices) }
                parentChoices = choices
                dateChoices = []
            }
            return
        }
        dateChoices = []
        parentChoices = []
        slashChoices = []
        slashState = nil
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

    private enum ChoiceKey { case highlight(Int), confirm }

    /// What a key does in a list with `count` choices and `highlight` highlighted: ↑ and ↓ move, wrapping (from nothing, to the last
    /// or first), and ↵ picks. Nil when the editor keeps the key.
    private static func move(_ highlight: Int?, count: Int, key: InlinePreviewKey) -> ChoiceKey? {
        switch key {
        case .moveUp: .highlight(highlight.map { ($0 + count - 1) % count } ?? count - 1)
        case .moveDown: .highlight(highlight.map { ($0 + 1) % count } ?? 0)
        case .confirm: .confirm
        case .confirmAndOpen, .cancel: nil
        }
    }

    /// A hardware keyboard's ↑/↓ move through the choices and ↵ picks one.
    private func handleLinkKey(_ key: InlinePreviewKey) -> Bool {
        if !slashChoices.isEmpty {
            switch key {
            case .moveUp: slashHighlight = (slashHighlight + slashChoices.count - 1) % slashChoices.count
            case .moveDown: slashHighlight = (slashHighlight + 1) % slashChoices.count
            case .confirm: insertSlashCommand(slashChoices[min(slashHighlight, slashChoices.count - 1)])
            case .confirmAndOpen, .cancel: return false
            }
            return true
        }
        if !dateChoices.isEmpty {
            guard let next = Self.move(dateHighlight, count: dateChoices.count, key: key) else { return false }
            switch next {
            case .highlight(let index): dateHighlight = index
            case .confirm:
                guard let dateHighlight else { return false }
                insertDate(dateChoices[min(dateHighlight, dateChoices.count - 1)])
            }
            return true
        }
        if !parentChoices.isEmpty {
            guard let next = Self.move(parentHighlight, count: parentChoices.count, key: key) else { return false }
            switch next {
            case .highlight(let index): parentHighlight = index
            case .confirm:
                guard let parentHighlight else { return false }
                insertParent(parentChoices[min(parentHighlight, parentChoices.count - 1)], in: attributeState)
            }
            return true
        }
        if let tagChoices, !tagChoices.isEmpty {
            switch key {
            case .moveUp: tagHighlight = (tagHighlight + tagChoices.count - 1) % tagChoices.count
            case .moveDown: tagHighlight = (tagHighlight + 1) % tagChoices.count
            case .confirm: insertTag(tagChoices[min(tagHighlight, tagChoices.count - 1)])
            case .confirmAndOpen, .cancel: return false
            }
            return true
        }
        guard !linkChoices.isEmpty else { return false }
        switch key {
        case .moveUp: linkHighlight = (linkHighlight + linkChoices.count - 1) % linkChoices.count
        case .moveDown: linkHighlight = (linkHighlight + 1) % linkChoices.count
        case .confirm: insertLink(linkChoices[min(linkHighlight, linkChoices.count - 1)])
        case .confirmAndOpen, .cancel: return false
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
        var extract: (() -> Void)?
        if let model = taskExtraction, let textView = slashCommand.textView {
            let location = textView.characterIndex(for: CGPoint(x: request.anchorRect.midX, y: request.anchorRect.midY))
            if location != NSNotFound, ExtractTask.canExtract(in: textView, at: location) {
                extract = { ExtractTask.perform(in: textView, at: location, model: model) }
            }
        }
        checkboxMenu.show(
            current: request.marker, anchor: request.anchorRect, items: TaskCheckboxStyle.referenceMenu,
            theme: theme, pick: request.setMarker, extract: extract
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

    private func showTextMenu(_ request: TextMenuRequest) {
        let target = TextMenuTarget(
            hasSelection: request.hasSelection,
            onLink: request.link != nil,
            canAddLink: links != nil && !request.selectionTouchesLink
                && AddLink.range(request.selection, selectedText: request.selectedText) != nil,
            canExtract: taskExtraction != nil && ExtractTask.extractableRange(request.selection, selectedText: request.selectedText) != nil,
            formats: Set(request.activeFormats.map(Self.command(for:))),
            block: Self.command(for: request.blockKind),
            isBody: request.blockKind == .body
        )
        textMenu.show(TextMenu.sections(for: target), anchor: request.anchorRect, theme: theme, pick: { runTextMenu($0, request) },
                      close: request.close)
    }

    private func runTextMenu(_ row: TextMenuRow, _ request: TextMenuRequest) {
        switch row.action {
        case .openLink:
            guard let link = request.link else { return }
            switch link.kind {
            case .wiki: onLinkClick(link.target)
            case .markdown: URL(string: link.target).map { _ = NSWorkspace.shared.open($0) }
            }
        case .copyLink:
            guard let link = request.link else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link.source, forType: .string)
        case .cut: request.cut()
        case .copy: request.copy()
        case .paste: request.paste()
        case .pasteAsPlainText: request.pasteAsPlainText()
        case .selectAll: request.selectAll()
        case .addLink:
            guard let links, let textView = slashCommand.textView, !request.selectionTouchesLink,
                  let range = AddLink.range(request.selection, selectedText: request.selectedText) else { return }
            let selected = (request.selectedText as NSString).substring(with: NSRange(location: range.location - request.selection.location,
                                                                                       length: range.length))
            addLinkMenu.show(text: selected, source: links, anchor: textView.firstRect(forCharacterRange: range, actualRange: nil),
                             theme: theme, pick: { choice in
                request.replaceSelection(ExtractTask.replacingTrimmed(in: request.selectedText) { _ in
                    AddLink.markdown(choice, selection: selected)
                } ?? request.selectedText)
            }, close: request.close)
        case .extractToTask:
            guard let model = taskExtraction, let textView = slashCommand.textView else { return }
            ExtractTask.perform(selection: request.selection, in: textView, model: model) { link in
                request.replaceSelection(ExtractTask.replacingTrimmed(in: request.selectedText) { _ in link } ?? request.selectedText)
            }
        case .body: request.setBlockKind(.body)
        case .command(let command):
            if let format = Self.format(for: command) {
                request.toggleFormat(format)
            } else if let kind = Self.blockKind(for: command) {
                request.setBlockKind(kind)
            } else if command == .link, let link = TextMenu.linkInsertion(selection: request.selection, selectedText: request.selectedText) {
                request.insert(link.text, selecting: link.selection, asBlock: false)
            } else {
                let text = (slashCommand.textView?.string ?? "") as NSString
                let line = text.lineRange(for: NSRange(location: min(request.selection.location, text.length), length: 0))
                let before = text.substring(with: NSRange(location: line.location, length: request.selection.location - line.location))
                let atLineStart = before.allSatisfy(\.isWhitespace)
                let insertion = command.insertion(followsBlankLine: request.followsBlankLine && atLineStart)
                request.insert(insertion.text, selecting: insertion.selection, asBlock: TextMenu.blockInsertions.contains(command))
            }
        case .submenu: break
        }
    }

    private static let formatCommands: [(SlashCommand, MarkdownFormat)] = [
        (.bold, .bold), (.italic, .italic), (.strikethrough, .strikethrough), (.highlight, .highlight), (.inlineCode, .inlineCode),
    ]

    private static let blockCommands: [(SlashCommand, TextMenuBlockKind)] = [
        (.heading1, .heading(1)), (.heading2, .heading(2)), (.heading3, .heading(3)), (.bulletedList, .bullet),
        (.numberedList, .numbered), (.task, .task), (.quote, .quote),
    ]

    private static func command(for format: MarkdownFormat) -> SlashCommand {
        formatCommands.first { $0.1 == format }!.0
    }

    private static func format(for command: SlashCommand) -> MarkdownFormat? {
        formatCommands.first { $0.0 == command }?.1
    }

    private static func command(for kind: TextMenuBlockKind) -> SlashCommand? {
        blockCommands.first { $0.1 == kind }?.0
    }

    private static func blockKind(for command: SlashCommand) -> TextMenuBlockKind? {
        blockCommands.first { $0.0 == command }?.1
    }

    /// A right-click on an image opens the embed menu; ⌘C, ⌘X and ⌘⌫ on a selected one copy, cut or delete it.
    private func handleImage(_ request: ImageEmbedRequest, model: AppModel) {
        guard let path = model.attachmentPath(forEmbed: request.name) else { return request.close() }
        switch request.action {
        case .copy:
            model.copyImage(path)
        case .cut:
            model.copyImage(path) { request.remove("Cut") }
        case .delete:
            model.imageDialog = .delete(path)
        case .menu:
            guard let window = NSApp.keyWindow else { return request.close() }
            FileMenu.shared.show(FileMenuAction.embedActions(for: path, model: model, cut: { request.remove("Cut") }),
                                 at: request.anchorRect.origin, in: window, theme: theme, onClose: request.close)
        }
    }

    private func showQueryMenu(_ state: SlashCommandState?) {
        switch state?.trigger {
        case nil:
            hideQueryMenus()
        case .slash:
            hideQueryMenus(except: .slash)
            showSlashMenu(state!)
        case .link, .embed:
            hideQueryMenus(except: .link)
            showLinkMenu(state!)
        case .tag:
            hideQueryMenus(except: .tag)
            showTagMenu(state!)
        case .date:
            hideQueryMenus(except: .date)
            showDateMenu(state!)
        case .parent:
            hideQueryMenus(except: .parent)
            showParentMenu(state!)
        }
    }

    /// Keys for any open picker come here (a query, upstream's `[[…]]` preview); each menu ignores them unless it's open.
    private func handleMenuKey(_ key: InlinePreviewKey) -> Bool {
        switch key {
        case .moveUp: slashMenu.handle(.up) || linkMenu.handle(.up) || tagMenu.handle(.up) || handleChoiceMenus(.up)
        case .moveDown: slashMenu.handle(.down) || linkMenu.handle(.down) || tagMenu.handle(.down) || handleChoiceMenus(.down)
        case .confirm: slashMenu.handle(.confirm) || linkMenu.handle(.confirm) || tagMenu.handle(.confirm) || handleChoiceMenus(.confirm)
        case .confirmAndOpen, .cancel: false
        }
    }

    private func handleChoiceMenus(_ key: ChoiceMenuKey) -> Bool {
        dateMenu.handle(key) || parentMenu.handle(key)
    }

    private func hideQueryMenus(except open: SlashCommandState.Trigger? = nil) {
        if open != .slash { slashMenu.hide() }
        if open != .link { linkMenu.hide() }
        if open != .tag { tagMenu.hide() }
        if open != .date { dateMenu.hide() }
        if open != .parent { parentMenu.hide() }
    }

    /// The `>` menu: the day the phrase gives, highlighted, then Today, Tomorrow, Next week and Pick a date….
    private func showDateMenu(_ state: SlashCommandState) {
        guard let model = taskAttributes else { return }
        let choices = DateChoice.choices(query: state.query, today: model.today, firstWeekday: Calendar.current.firstWeekday,
                                         order: .system, includesPick: true)
        dateMenu.show(choices, highlight: DateChoice.highlight(in: choices), anchor: state.anchorRect, theme: theme, pick: { [self] choice in
            if choice.kind == .pick { pickDate(in: state) } else { insertDate(choice) }
        }, dismiss: { [slashCommand] in slashCommand.dismiss() })
    }

    /// Opens the calendar for the `>` query; its pick replaces the typed `>…` with the day.
    private func pickDate(in state: SlashCommandState) {
        guard let model = taskAttributes, let textView = slashCommand.textView, let window = NSApp.keyWindow,
              let replace = replacingQuery(state) else { return }
        dateMenu.hide()
        calendar.show(.due, selected: nil, other: nil, today: model.today, theme: theme, below: state.anchorRect, in: window) { [calendar] date in
            calendar.hide()
            window.makeFirstResponder(textView)
            if let date { _ = replace(">\(date) ") }
        }
    }

    /// The `@` menu: the areas and projects the typed text is in, and New project for it.
    private func showParentMenu(_ state: SlashCommandState) {
        guard let model = taskAttributes else { return }
        let choices = ParentChoice.choices(index: model.index, query: state.query)
        parentMenu.show(choices, highlight: ParentChoice.highlight(in: choices), anchor: state.anchorRect, theme: theme,
                        pick: { [self] in insertParent($0, in: state) }, dismiss: { [slashCommand] in slashCommand.dismiss() })
    }

    /// A click on a drawn date opens the calendar, and on a parent the areas and projects and Remove; a pick replaces the attribute.
    private func showAttributeMenu(_ click: TaskAttributeClick) {
        guard let model = taskAttributes, let window = NSApp.keyWindow else { return }
        switch click.kind {
        case .due:
            let current = LocalDate(String(click.source.dropFirst()))
            calendar.show(.due, selected: current, other: nil, today: model.today, theme: theme, below: click.anchorRect, in: window) { [calendar] date in
                calendar.hide()
                if let date { click.replace(">\(date)") } else { removeAttribute(click) }
            }
        case .parent:
            let current = String(click.source.dropFirst(3).dropLast(2))
            let choices = ParentChoice.choices(index: model.index, query: "") + [.remove]
            parentChipMenu.show(choices, highlight: choices.firstIndex { $0.title == current }, anchor: click.anchorRect, theme: theme,
                                pick: { [parentChipMenu] choice in
                parentChipMenu.hide()
                if choice.kind == .remove { removeAttribute(click) } else { click.replace(choice.token) }
            }, dismiss: { [parentChipMenu] in parentChipMenu.hide() })
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
            contentGap: 6,
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
            wikiLinks: TitleResolver(titles: linkTargets, statuses: linkStatuses),
            images: AttachmentImages(root: links?.vault?.root, paths: links?.attachments ?? []),
            syntaxHighlighter: CodeBlockStyle(background: theme.code)
        )
        // Images stay drawn as the caret passes; a missing one is muted and dashed, as an unresolved link.
        config.imageEmbed.revealsSourceAtCaret = false
        config.imageEmbed.missingText = theme.muted.withAlphaComponent(0.6)
        config.imageEmbed.file.background = theme.code
        config.imageEmbed.file.border = theme.border
        config.imageEmbed.file.badge = theme.link
        config.imageEmbed.file.text = theme.strong
        config.imageEmbed.file.badgeFillAlpha = theme.isDark ? 0.2 : 0.14
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
        if let model = taskAttributes {
            config.taskAttributes = Self.taskAttributeStyle(theme: theme, index: model.index, today: model.today, generation: model.indexGeneration)
        }
        config.lists.autoClosePairsEnabled = autocomplete.brackets
        config.lists.autoCloseFormattingEnabled = autocomplete.formatting
        config.lists.autoCloseWikiLinksEnabled = autocomplete.wikiLinks
        config.heightBehavior = fitsContent ? .fitsContent : .scrolls
        config.textInsets = TextInsets(horizontal: 16, vertical: 8)
        return config
    }

    /// The first file URL among `urls` that is a regular-file attachment, other than an image or a plain-text file.
    private nonisolated static func pastedFile(in urls: [URL]) -> URL? {
        urls.first { url in
            let ext = url.pathExtension.lowercased()
            return url.isFileURL && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && Vault.isAttachment(url.lastPathComponent) && !["markdown", "mdown", "mkd", "txt", "text"].contains(ext)
                && UTType(filenameExtension: ext)?.conforms(to: .image) != true
        }
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

/// Resolves a link by its title, as `WikiLink` reads it, against the lowercased titles of the folder's files. A link to a
/// task carries its status's checkbox marker.
nonisolated struct TitleResolver: WikiLinkResolver {
    let titles: Set<String>
    var statuses: [String: Status] = [:]

    func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? {
        guard let link = WikiLink(inner: displayName) else { return nil }
        let title = link.title.lowercased()
        guard titles.contains(title) else { return nil }
        return WikiLinkResolution(id: displayName, exists: true, marker: statuses[title].map(StatusCheckbox.marker(for:)))
    }

    func fingerprint() -> AnyHashable { [AnyHashable(titles), AnyHashable(statuses)] }
}

/// Draws `![[name.png]]` from the folder's images, found as `Vault.attachmentPath(for:in:)` finds them. An image keeps
/// its pixel size in points, so the editor fits a large one to its width. An embed of another kind of file is a file block.
nonisolated struct AttachmentImages: EmbeddedImageProvider {
    let root: URL?
    let paths: [String]

    func image(for request: EmbeddedImageRequest) -> PlatformImage? {
        guard let root, let embed = WikiLink(inner: request.name),
              let path = Vault.attachmentPath(for: embed, in: paths) else { return nil }
        return Self.load(Vault(root: root).url(for: path))
    }

    func isFile(for request: EmbeddedImageRequest) -> Bool {
        guard let embed = WikiLink(inner: request.name), let path = Vault.attachmentPath(for: embed, in: paths) else { return false }
        return !Vault.isImage(path)
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

/// Above the keyboard: undo, redo, `/`, subtask box, `#`, `>` and `@`, Aa (the formatting keyboard) and hide keyboard.
/// It's hosted outside SwiftUI's environment, so it takes the theme.
private struct EditorKeyboardBar: View {
    let theme: Theme
    let proxy: SlashCommandProxy
    /// Settings ▸ Editor's Wikilinks switch.
    let closesWikiLinks: Bool
    let haptics: Bool
    /// Whether `>` and `@` show on a subtask's line.
    let hasAttributeKeys: Bool
    let hideKeyboard: () -> Void
    @State private var hides = 0
    @State private var toggles = 0
    @State private var onSubtask = false
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var selectionChanges: AnyCancellable?
    @State private var formats = FormattingState()
    /// The formatting keyboard, while it's the text view's input view.
    @State private var formattingKeyboard: UIHostingController<FormattingKeyboard>?
    /// The system keyboard's height without the bar, which the formatting keyboard takes.
    @State private var keyboardHeight: CGFloat = 291

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    button("Undo", "arrow.uturn.backward") {
                        proxy.textView?.undoManager?.undo()
                        Task { refresh() }
                    }
                        .disabled(!canUndo)
                        .opacity(canUndo ? 1 : 0.35)
                    button("Redo", "arrow.uturn.forward") {
                        proxy.textView?.undoManager?.redo()
                        Task { refresh() }
                    }
                        .disabled(!canRedo)
                        .opacity(canRedo ? 1 : 0.35)
                    Divider().frame(height: 24).padding(.horizontal, 2)
                    Button { proxy.type("/") } label: {
                        Text(verbatim: "/")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.color(\.accent))
                            .frame(width: 34, height: 36)
                            .background(theme.tagFill(), in: .capsule)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Insert Formatting")
                    button("Subtask", "checkmark.square") { if let textView = proxy.textView { PhoneSubtask.perform(in: textView) } }
                    Button { proxy.type("#") } label: {
                        Text(verbatim: "#")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.color(\.fg))
                            .frame(width: 34, height: 36)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Insert #")
                    if hasAttributeKeys, onSubtask {
                        attributeKey(">", "Insert due date")
                        attributeKey("@", "Insert parent")
                    }
                }
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.never)
            Button {
                toggles += 1
                toggleFormattingKeyboard()
            } label: {
                Text(verbatim: formattingKeyboard == nil ? "Aa" : "ABC")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.color(\.fg))
                    .contentTransition(.identity)
                    .frame(width: 34, height: 36)
                    .contentShape(.rect)
                    .transaction { $0.animation = nil }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(formattingKeyboard == nil ? "Show Formatting Keyboard" : "Show Letters Keyboard")
            .padding(.horizontal, 2)
            Divider().frame(height: 24)
            button("Hide Keyboard", "keyboard.chevron.compact.down") {
                hides += 1
                hideKeyboard()
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 44)
        .glassEffect(in: .capsule)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .sensoryFeedback(.impact(weight: .light), trigger: hides) { _, _ in haptics }
        .sensoryFeedback(.impact(weight: .light), trigger: toggles) { _, _ in haptics }
        .onAppear {
            refresh()
            selectionChanges = proxy.textView?.publisher(for: \.selectedTextRange).sink { _ in refresh() }
        }
        .onChange(of: theme) { formattingKeyboard?.rootView = formattingKeyboardView() }
        .onChange(of: haptics) { formattingKeyboard?.rootView = formattingKeyboardView() }
        .onChange(of: closesWikiLinks) { formattingKeyboard?.rootView = formattingKeyboardView() }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidChangeNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)) { note in
            if note.object as? UITextView === proxy.textView, formattingKeyboard != nil { toggleFormattingKeyboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard formattingKeyboard == nil, let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let bar = proxy.textView?.inputAccessoryView?.bounds.height, frame.height - bar > 200 else { return }
            keyboardHeight = frame.height - bar
        }
    }

    /// Whether the caret is on a task line after its box, where `>` and `@` open their menus (the editor's rule); the
    /// formats at the caret; and whether there's an undo or redo.
    private func refresh() {
        guard let textView = proxy.textView else { return }
        let text = textView.text as NSString
        let caret = min(textView.selectedRange.location, text.length)
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        onSubtask = TaskAttributeSyntax.isTaskAttributeLine(text.substring(with: NSRange(location: start, length: caret - start)))
        let line = text.substring(with: NSRange(location: start, length: contentsEnd - start))
        formats.line = LineFormat.state(of: line[...])
        formats.inline = LineFormat.inlineFormats(in: line, at: caret - start)
        canUndo = textView.undoManager?.canUndo ?? false
        canRedo = textView.undoManager?.canRedo ?? false
    }

    /// Swaps the system keyboard for the formatting keyboard, at its height, or back.
    private func toggleFormattingKeyboard() {
        guard let textView = proxy.textView else { return }
        if formattingKeyboard != nil {
            formattingKeyboard = nil
            textView.inputView = nil
        } else {
            let host = UIHostingController(rootView: formattingKeyboardView())
            host.view.backgroundColor = .clear
            host.safeAreaRegions = []
            let input = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: keyboardHeight), inputViewStyle: .keyboard)
            host.view.frame = input.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            input.addSubview(host.view)
            formattingKeyboard = host
            textView.inputView = input
        }
        textView.reloadInputViews()
    }

    private func formattingKeyboardView() -> FormattingKeyboard {
        FormattingKeyboard(theme: theme, state: formats, haptics: haptics, perform: perform)
    }

    private func perform(_ action: FormattingAction) {
        guard let textView = proxy.textView else { return }
        let selection = textView.selectedRange
        // Inserts go after a selection rather than over it.
        switch action {
        case .block, .callout, .embed: textView.selectedRange = NSRange(location: NSMaxRange(selection), length: 0)
        default: break
        }
        let caret = textView.selectedRange.location
        switch action {
        case let .line(format):
            let plan = LineFormat.plan(format, in: textView.text, caret: caret)
            if let start = textView.position(from: textView.beginningOfDocument, offset: plan.range.location),
               let end = textView.position(from: start, offset: plan.range.length),
               let range = textView.textRange(from: start, to: end) {
                textView.replace(range, withText: plan.text)
                textView.selectedRange = plan.selection
            }
        case .subtask: PhoneSubtask.perform(in: textView)
        case .inline(.bold): proxy.apply(.bold)
        case .inline(.italic): proxy.apply(.italic)
        case .inline(.strikethrough): proxy.apply(.strikethrough)
        case .inline(.highlight): proxy.apply(.highlight)
        case .inline(.code): proxy.apply(.inlineCode)
        case let .block(command): insert(LineFormat.blockInsertion(command, in: textView.text, caret: caret))
        case let .callout(type): insert(LineFormat.blockInsertion(.callout, callout: type, in: textView.text, caret: caret))
        case .wikiLink: PhoneWikiLink.perform(with: proxy, closes: closesWikiLinks)
        case .link:
            let text = (textView.text as NSString).substring(with: selection)
            insert(text.isEmpty ? SlashCommand.link.insertion()
                   : ("[\(text)]()", NSRange(location: (text as NSString).length + 3, length: 0)))
        case .embed: "![[".forEach { proxy.type(String($0)) }
        case .outdent: proxy.outdent()
        case .indent: proxy.indent()
        case .deleteBackward: textView.deleteBackward()
        }
        refresh()
    }

    /// Types `key` as the keyboard does, after a space when the caret follows text.
    private func attributeKey(_ key: String, _ label: String) -> some View {
        Button {
            if let textView = proxy.textView, let text = textView.text as NSString?, textView.selectedRange.location > 0,
               !CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(text.character(at: textView.selectedRange.location - 1)) ?? "a") {
                proxy.type(" ")
            }
            proxy.type(key)
        } label: {
            Text(verbatim: key)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.color(\.fg))
                .frame(width: 34, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func button(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(theme.color(\.fg))
                .frame(width: 34, height: 36)
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

/// The subtask button: makes the caret's line (or each selected line) a subtask, or completes (or reopens) it, as ⌘L does on the Mac.
private enum PhoneSubtask {
    static func perform(in textView: UITextView) {
        guard let plan = SubtaskLine.plan(in: textView.text, selection: textView.selectedRange) else { return }
        textView.selectedRange = plan.range
        textView.insertText(plan.text)
        textView.selectedRange = plan.selection
    }
}
#endif
