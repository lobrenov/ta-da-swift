// The link menu: files to link after `[[`, images to embed after `![[`.
// The editor engine tracks the query and routes the keys; LiveEditor shows the choices in a popup menu under the
// `[[` on the Mac and in a list above the keyboard bar on iPhone.
import SwiftUI
import TaDaCore

/// What a query lists: files after `[[`, images after `![[`.
enum LinkMenuKind {
    case link, embed

    /// What ↵ does, in the Mac menu's footer.
    var confirmLabel: String { self == .link ? "Link" : "Embed" }
}

/// What the link menu searches, and embeds draw from: the folder's files and images, the files opened last and the
/// open one, which the menu leaves out.
struct LinkMenuSource {
    var index = VaultIndex()
    var vault: Vault?
    /// The folder's images, most recently changed first.
    var attachments: [String] = []
    /// Paths, most recent first.
    var recent: [String] = []
    var openPath: String?
}

/// A row of the link menu: a file to link or an image to embed.
struct LinkChoice: Hashable, Identifiable {
    enum Icon: Hashable {
        case task(Status)
        /// Done/total of the project's tasks.
        case project(Double)
        case area
        case note
        case image(URL)
    }

    let path: String
    let icon: Icon
    /// The file's title, or the image's filename.
    let title: String
    /// A task's project or area, or Loose task; Project or Area; a note's folder, or Note; nothing for an image.
    let hint: String
    /// What an image's embed names it by: its filename, or its path when the filename finds another image first.
    var embedTarget: String?

    var id: String { path }

    /// The text that replaces the query: `[[Title]]` or `![[name.png]]`.
    var markdown: String {
        if case .image = icon { "![[\(embedTarget ?? title)]]" } else { "[[\(title)]]" }
    }
}

/// The choices for one editor's queries, and the images' thumbnails.
final class LinkMenuSearch {
    var source = LinkMenuSource()

    /// The most rows a query lists.
    static let limit = 50
    /// How many recent files an empty `[[` lists.
    static let recentCount = 8

    /// The choices for `query`, best match first, under a label while nothing is typed.
    func choices(_ kind: LinkMenuKind, query: String) -> (label: String?, choices: [LinkChoice]) {
        switch kind {
        case .link: links(query)
        case .embed: embeds(query)
        }
    }

    /// A small thumbnail of an image file, from `ThumbnailCache`; nil when it can't be read (SVG, for one).
    func thumbnail(_ url: URL) -> CGImage? {
        ThumbnailCache.decode(url, pixels: 96)
    }

    /// Recent files first, then the rest by title, logged files left out; an empty query lists only the recent ones, or every file when
    /// none has been opened.
    private func links(_ query: String) -> (label: String?, choices: [LinkChoice]) {
        let index = source.index
        let recent = source.recent.compactMap { index[$0] }.filter { $0.path != source.openPath && !$0.isLogged }.prefix(Self.recentCount)
        let others = index.liveItems.filter { $0.path != source.openPath && !recent.contains($0) }.sorted(by: VaultIndex.byTitle)
        if query.trimmingCharacters(in: .whitespaces).isEmpty, !recent.isEmpty {
            return ("Recent", recent.map(choice))
        }
        return (nil, LinkSearch.rank(Array(recent) + others, query: query, name: \.title).prefix(Self.limit).map(choice))
    }

    private func embeds(_ query: String) -> (label: String?, choices: [LinkChoice]) {
        guard let vault = source.vault else { return (nil, []) }
        let name = { (path: String) in String(path.split(separator: "/").last ?? "") }
        let choices = LinkSearch.rank(source.attachments, query: query, name: name).prefix(Self.limit).map { path in
            LinkChoice(path: path, icon: .image(vault.url(for: path)), title: name(path), hint: "",
                       embedTarget: Vault.embedTarget(for: path, in: source.attachments))
        }
        return (query.trimmingCharacters(in: .whitespaces).isEmpty ? "Attachments" : nil, choices)
    }

    private func choice(_ item: Item) -> LinkChoice {
        let index = source.index
        switch item.properties.kind {
        case .task:
            return LinkChoice(path: item.path, icon: .task(item.properties.status), title: item.title,
                              hint: index.parent(of: item)?.title ?? "Loose task")
        case .project:
            return LinkChoice(path: item.path, icon: .project(index.progress(of: item).fraction), title: item.title, hint: "Project")
        case .area:
            return LinkChoice(path: item.path, icon: .area, title: item.title, hint: "Area")
        case .note:
            let folder = Vault.folder(of: item.path)
            return LinkChoice(path: item.path, icon: .note, title: item.title, hint: folder.isEmpty ? "Note" : folder)
        }
    }
}

/// A link menu row's icon: a task's status box, a project's ring, an area's cube, a note's page or an image's thumbnail.
struct LinkChoiceIcon: View {
    let icon: LinkChoice.Icon
    let search: LinkMenuSearch
    let theme: Theme
    /// The status box's side; the slot is half as wide again.
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch icon {
            case .task(let status):
                let (marker, tint) = StatusCheckbox.box(for: status, theme: theme)
                InlineCheckboxView(marker: marker, tint: tint, background: theme.bg)
                    .frame(width: size, height: size)
            case .project(let fraction):
                ProgressRing(fraction: fraction)
                    .foregroundStyle(theme.color(\.accent))
                    .scaleEffect(size / 14)
            case .area:
                AreaIcon(size: size + 2)
            case .note:
                NoteIcon(size: size + 2)
            case .image(let url):
                if let image = search.thumbnail(url) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size * 10 / 7, height: size * 10 / 7)
                        .clipShape(.rect(cornerRadius: 4))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: size - 1))
                        .foregroundStyle(theme.color(\.muted))
                }
            }
        }
        .frame(width: size * 10 / 7, height: size * 10 / 7)
        .environment(\.theme, theme)
    }
}

#if os(macOS)
import AppKit

/// Shows, moves through and picks from the link menu. Owned by LiveEditor.
final class LinkMenuController {
    enum Key { case up, down, confirm }

    let search = LinkMenuSearch()
    private lazy var linkMenu = menu(.link)
    private lazy var embedMenu = menu(.embed)
    private var shown: (kind: LinkMenuKind, choices: [LinkChoice])?

    /// Shows the menu under `anchor` (the `[[`, in screen coordinates), or refreshes it.
    func show(_ kind: LinkMenuKind, query: String, anchor: CGRect, theme: Theme,
              pick: @escaping (LinkChoice) -> Void, dismiss: @escaping () -> Void) {
        guard anchor != .zero, let parent = NSApp.keyWindow else { return }
        let (label, choices) = search.choices(kind, query: query)
        let menu = kind == .link ? linkMenu : embedMenu
        (kind == .link ? embedMenu : linkMenu).hide()
        let highlight = shown.map { $0.kind == kind && $0.choices == choices } == true ? menu.highlight : 0
        shown = (kind, choices)
        // A click elsewhere or a scroll ends the query; the typed text stays.
        menu.onDismiss = dismiss
        menu.show([PopupMenuSection(label: label, items: choices)], highlight: choices.isEmpty ? nil : highlight,
                  theme: theme, below: anchor, inset: 8, gap: 6, in: parent, pick: pick)
    }

    func hide() {
        linkMenu.hide()
        embedMenu.hide()
        shown = nil
    }

    /// Returns `true` when the menu used the key. ↵ with no matches falls through to the editor.
    func handle(_ key: Key) -> Bool {
        guard let menu = [linkMenu, embedMenu].first(where: \.isOpen) else { return false }
        switch key {
        case .up: menu.move(by: -1)
        case .down: menu.move(by: 1)
        case .confirm: return menu.pickHighlighted()
        }
        return true
    }

    private func menu(_ kind: LinkMenuKind) -> PopupMenu<LinkChoice, LinkMenuRow> {
        PopupMenu(style: .full(confirm: kind.confirmLabel, maxListHeight: 284), takesKeys: false,
                  emptyText: "No matching files") { [search] choice, isHighlighted, theme in
            LinkMenuRow(choice: choice, isHighlighted: isHighlighted, theme: theme, search: search)
        }
    }
}

extension LinkChoice: PopupMenuItem {
    var accessibilityValue: String { hint }
}

struct LinkMenuRow: View {
    let choice: LinkChoice
    let isHighlighted: Bool
    let theme: Theme
    let search: LinkMenuSearch

    var body: some View {
        HStack(spacing: 10) {
            LinkChoiceIcon(icon: choice.icon, search: search, theme: theme)
            Text(choice.title)
                .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(choice.hint)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.color(\.muted))
                .lineLimit(1)
                .frame(maxWidth: 96, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
