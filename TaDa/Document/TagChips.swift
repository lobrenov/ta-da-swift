// The Tags row under a file's property chips: its `tags:` as filled chips (× on hover removes one), + Tag for
// tagMenu, then "In text" and the body's tags, read-only. A chip click opens that tag's page.
import SwiftUI
import TaDaCore
#if os(macOS)

struct TagChipRow: View {
    let model: AppModel
    let item: Item
    @State private var anchor = ScreenAnchor()
    @Environment(\.theme) private var theme

    var body: some View {
        let written = item.tags.filter(\.inFrontmatter)
        let inText = item.tags.filter { !$0.inFrontmatter }
        WrappingHStack(spacing: 6) {
            ForEach(written, id: \.tag.path) { use in
                TagChip(tag: use.tag, filled: true, open: { model.show(.tag(use.tag.path)) },
                        remove: { Task { await model.removeTag(use.tag, from: item.path) } })
            }
            Button { PropertyPicker.shared.pickTags(of: item, model: model, anchor: anchor) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    Text("Tag")
                }
            }
            .buttonStyle(AddTagStyle(isOpen: PropertyPicker.shared.isOpen(item.path, "tags")))
            .background(ScreenAnchorReader(anchor: anchor))
            .onChange(of: model.propertyMenuRequest) { _, request in
                guard let request, request.menu == .tags, request.onChip, request.anchor == item.path else { return }
                model.propertyMenuRequest = nil
                PropertyPicker.shared.pickTags(of: item, model: model, anchor: anchor)
            }
            .accessibilityLabel("Add a tag")
            if !inText.isEmpty {
                Text("In text")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.leading, 6)
                ForEach(inText, id: \.tag.path) { use in
                    TagChip(tag: use.tag, filled: false, open: { model.show(.tag(use.tag.path)) }, remove: nil)
                }
            }
        }
        .font(.system(size: 12.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tags")
        .onDisappear { PropertyPicker.shared.close(path: item.path) }
    }
}

/// A tag's glyph and name, its parent path muted. Filled chips are `tags:`: tinted, with a × on hover when they can
/// be removed. Others are outlined.
private struct TagChip: View {
    let tag: Tag
    let filled: Bool
    let open: () -> Void
    let remove: (() -> Void)?
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Button(action: open) {
                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.color(\.accent))
                    TagName(tag: tag)
                        .foregroundStyle(theme.color(filled ? \.strong : \.fg))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Show files tagged #\(tag.name)")
            if let remove, hovering {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.color(\.fg))
                        .frame(width: 16, height: 16)
                        .background(theme.color(\.surface), in: .circle)
                }
                .buttonStyle(.plain)
                .padding(.leading, -1)
                .accessibilityLabel("Remove tag \(tag.name)")
            }
        }
        .lineLimit(1)
        .padding(.leading, 9)
        .padding(.trailing, remove != nil && hovering ? 6 : 11)
        .frame(height: 26)
        .background(filled ? theme.tagFill(hovering: hovering) : .clear, in: .capsule)
        .overlay(Capsule().strokeBorder(filled ? theme.tagRing : theme.color(\.border)))
        .contentShape(.capsule)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag \(tag.name)")
        .accessibilityActions {
            Button("Show files tagged \(tag.name)", action: open)
            if let remove { Button("Remove tag", action: remove) }
        }
    }
}

/// + Tag: a dashed capsule, `surface` under the pointer or while tagMenu is open.
private struct AddTagStyle: ButtonStyle {
    let isOpen: Bool

    func makeBody(configuration: Configuration) -> some View {
        AddTagBody(label: configuration.label, lit: configuration.isPressed || isOpen)
    }
}

private struct AddTagBody<Label: View>: View {
    let label: Label
    let lit: Bool
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        let lit = lit || hovering
        label
            .foregroundStyle(theme.color(lit ? \.strong : \.muted))
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .frame(height: 26)
            .background(lit ? theme.color(\.surface) : .clear, in: .capsule)
            .overlay {
                if !lit {
                    Capsule().strokeBorder(theme.color(\.surface), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .contentShape(.capsule)
            .onHover { hovering = $0 }
    }
}

/// A tag's glyph, path and count, ticked when it's in `tags:` and greyed "in text" when it's only in the body; or
/// Create with a plus.
struct TagChoiceRow: View {
    let choice: TagChoice
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            switch choice {
            case .tag(let tag, let count, let inFile, let inText):
                Image(systemName: "tag")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.color(inText ? \.muted : \.accent))
                    .frame(width: 16)
                TagName(tag: tag)
                    .foregroundStyle(theme.color(inText ? \.muted : isHighlighted ? \.strong : \.fg))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if inFile {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.color(\.accent))
                } else if inText {
                    Text("in text").font(.system(size: 11)).foregroundStyle(theme.color(\.muted))
                } else {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(theme.color(\.muted))
                }
            case .create:
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.accent))
                    .frame(width: 16)
                Text(choice.title)
                    .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
        }
        .environment(\.theme, theme)
    }
}
#endif

/// A tag's path: the parent segments muted, the last one plain.
struct TagName: View {
    let tag: Tag
    @Environment(\.theme) private var theme

    var body: some View {
        let parent = tag.parent.map { $0.name + "/" } ?? ""
        Text("\(Text(parent).foregroundStyle(theme.color(\.muted)))\(Text(tag.leaf))")
    }
}

extension Theme {
    /// A tag chip's fill: `accent` at 14% in dark schemes and 10% in light ones, stronger under the pointer.
    func tagFill(hovering: Bool = false) -> Color {
        color(\.accent).opacity(hovering ? (isDark ? 0.24 : 0.18) : (isDark ? 0.14 : 0.10))
    }

    /// A tag chip's ring: `accent` at 32% in dark schemes and 28% in light ones.
    var tagRing: Color { color(\.accent).opacity(isDark ? 0.32 : 0.28) }
}

/// A row of tagMenu.
enum TagChoice: PopupMenuItem {
    /// A tag and how many files carry it or a child. `inFile`: in the file's `tags:` (ticked); `inText`: only in its
    /// body, so it can't be picked.
    case tag(Tag, count: Int, inFile: Bool, inText: Bool)
    /// Adds a tag no file carries yet.
    case create(Tag)

    static let prompt = "Add a tag"

    var title: String {
        switch self {
        case .tag(let tag, _, _, _): tag.name
        case .create(let tag): "Create #\(tag.name)"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .tag(_, let count, let inFile, let inText): inFile ? "In this file" : inText ? "In the text" : count == 1 ? "1 file" : "\(count) files"
        case .create: ""
        }
    }

    var isPickable: Bool {
        if case .tag(_, _, _, true) = self { false } else { true }
    }

    /// tagMenu for `item` and what's typed. Unsearched: In this file (`tags:`, then the body's), then All tags with
    /// counts, by path. Typing keeps the tags with a segment starting with the text, and puts Create first when no
    /// tag has that path. The row of the tag at `keeping` is highlighted (the one just toggled), else the first
    /// pickable row.
    static func menu(item: Item, tree: [TagNode], query: String, keeping: String? = nil)
        -> (sections: [PopupMenuSection<TagChoice>], highlight: Int?) {
        let text = query.trimmingCharacters(in: .whitespaces)
        let typed = Tag(text)
        var counts: [String: (tag: Tag, count: Int)] = [:]
        func visit(_ nodes: [TagNode]) {
            for node in nodes {
                counts[node.tag.path] = (node.tag, node.count)
                visit(node.children)
            }
        }
        visit(tree)
        func matches(_ tag: Tag) -> Bool {
            guard let typed else { return true }
            return ([tag.path] + tag.path.indices.filter { tag.path[$0] == "/" }.map { String(tag.path[tag.path.index(after: $0)...]) })
                .contains { $0.hasPrefix(typed.path) }
        }
        let inFile = item.tags.filter { matches($0.tag) }.map { use in
            TagChoice.tag(use.tag, count: counts[use.tag.path]?.count ?? 0, inFile: use.inFrontmatter, inText: !use.inFrontmatter)
        }
        let own = Set(item.tags.map(\.tag.path))
        let all = counts.values.filter { !own.contains($0.tag.path) && matches($0.tag) }.sorted { $0.tag.path < $1.tag.path }
            .map { TagChoice.tag($0.tag, count: $0.count, inFile: false, inText: false) }
        var sections: [PopupMenuSection<TagChoice>] = []
        if let typed, counts[typed.path] == nil, !own.contains(typed.path) {
            sections.append(PopupMenuSection(items: [.create(typed)]))
        }
        sections.append(PopupMenuSection(label: "In this file", items: inFile))
        sections.append(PopupMenuSection(label: "All tags", items: all))
        sections = sections.filter { !$0.items.isEmpty }
        let items = sections.flatMap(\.items)
        let kept = keeping.flatMap { path in items.firstIndex { if case .tag(let tag, _, _, _) = $0 { tag.path == path } else { false } } }
        return (sections, kept ?? items.firstIndex(where: \.isPickable))
    }
}
