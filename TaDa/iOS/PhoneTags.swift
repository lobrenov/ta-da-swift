// Tags on iPhone: the Tags screen (Untagged and the tag tree), a tag's screen (as the Mac's tagBrowser, with a + that
// makes a task with the tag), a file's Tags row, and the sheet that adds and removes its tags.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneTagsScreen: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let tagged = model.taggedCount
        List {
            Section {
                NavigationLink(value: PhoneRoute.tag(nil)) {
                    row(Text("Untagged"), symbol: "tag.slash", tint: \.muted, count: model.untaggedCount)
                }
            } header: {
                Text("\(model.tagCount == 1 ? "1 tag" : "\(model.tagCount) tags") · \(tagged == 1 ? "1 tagged file" : "\(tagged) tagged files")")
                    .textCase(nil)
            }
            if !model.tagTree.isEmpty {
                Section("All tags") {
                    ForEach(model.visibleTags, id: \.node.id) { entry in
                        tagRow(entry.node, depth: entry.depth)
                    }
                }
            }
        }
        .listRowBackground(theme.color(\.code))
        .scrollContentBackground(.hidden)
        .background(theme.color(\.bg))
        .navigationTitle("Tags")
    }

    /// A tag: its fold chevron (for a parent), then its glyph, last segment and count, 28pt in per level.
    private func tagRow(_ node: TagNode, depth: Int) -> some View {
        let path = node.tag.path
        let folded = model.isTagFolded(path)
        return HStack(spacing: 0) {
            Group {
                if node.children.isEmpty {
                    Color.clear
                } else {
                    Button { withAnimation(.snappy) { model.toggleTagFolded(path) } } label: {
                        Image(systemName: "chevron.right")
                            .scaledFont(size: 13, weight: .bold)
                            .rotationEffect(.degrees(folded ? 0 : 90))
                            .foregroundStyle(theme.color(\.accent))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(folded ? "Expand \(node.tag.leaf)" : "Collapse \(node.tag.leaf)")
                }
            }
            .frame(width: 22)
            .padding(.trailing, 8)
            NavigationLink(value: PhoneRoute.tag(path)) {
                row(Text(node.tag.leaf), symbol: "tag", tint: \.accent, count: node.count)
            }
        }
        .padding(.leading, CGFloat(depth) * 28 - 8)
        .listRowBackground(theme.color(\.code))
    }

    private func row(_ title: Text, symbol: String, tint: KeyPath<Theme, PlatformColor>, count: Int) -> some View {
        HStack {
            Label {
                title.foregroundStyle(theme.color(\.fg)).lineLimit(1)
            } icon: {
                Image(systemName: symbol).foregroundStyle(theme.color(tint))
            }
            Spacer()
            Text("\(count)").foregroundStyle(theme.color(\.muted))
        }
    }
}

// MARK: A tag's screen

struct PhoneTagScreen: View {
    let model: AppModel
    /// The tag's path; nil for Untagged.
    let path: String?
    /// The spelling last shown, kept once no file carries the tag.
    @State private var lastTag: Tag?
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    private var tag: Tag? {
        guard let path else { return nil }
        return model.tag(at: path) ?? lastTag.flatMap { $0.path == path ? $0 : nil } ?? Tag(path)
    }

    var body: some View {
        let tag = tag
        if let page = model.phoneTagPages[path] {
            list(page, tag: tag)
        } else {
            Color.clear.onAppear { model.showPhoneTagPage(path) }
        }
    }

    private func list(_ page: TagBrowser, tag: Tag?) -> some View {
        let open = page.groups.flatMap(\.tasks)
        let foldKey = "tag:" + (path ?? "")
        // Completed starts folded: a stored entry for it means it was opened.
        let completedFolded = !model.isFolded("Completed", in: foldKey)
        let shown = open + (completedFolded ? [] : page.completed)

        return PhoneList(model: model, title: tag?.name ?? "Untagged", subtitle: subtitle(page, open: open.count, untagged: tag == nil),
                  icon: AnyView(Image(systemName: tag == nil ? "tag.slash" : "tag")
                      .scaledFont(size: 26)
                      .foregroundStyle(theme.color(tag == nil ? \.muted : \.accent))),
                  pickable: shown.map(\.path), add: newTask) {
            EmptyView()
        } content: {
            if !page.children.isEmpty {
                WrappingHStack(spacing: 8) {
                    ForEach(page.children) { child in
                        Button { nav.push(.tag(child.tag.path)) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "tag").scaledFont(size: 12, weight: .semibold).foregroundStyle(theme.color(\.accent))
                                Text(child.tag.leaf).foregroundStyle(theme.color(\.strong))
                                Text("\(child.count)").foregroundStyle(theme.color(\.muted))
                            }
                            .scaledFont(size: 15)
                            .padding(.horizontal, 12)
                            .scaledMinHeight(32)
                            .background(theme.tagFill(), in: .capsule)
                            .overlay(Capsule().strokeBorder(theme.tagRing))
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tag \(child.tag.name), \(child.count) files")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            ForEach(page.areasAndProjects) { item in
                if item.properties.kind == .area {
                    PhoneAreaRow(model: model, area: item)
                } else {
                    PhoneProjectRow(model: model, progress: model.index.progress(of: item))
                }
            }
            if open.isEmpty {
                Text(tag == nil ? "Every open task has a tag." : "No open tasks carry this tag.")
                    .scaledFont(size: 15)
                    .foregroundStyle(theme.color(\.muted))
                    .padding(16)
            }
            ForEach(page.groups) { group in
                switch group.parent {
                case let parent? where parent.properties.kind == .area:
                    PhoneAreaHeader(area: parent)
                case let parent?:
                    PhoneProjectHeader(project: parent, progress: model.index.progress(of: parent))
                case nil:
                    looseHeader
                }
                ForEach(group.tasks) { PhoneTaskRow(model: model, item: $0) }
            }
            if !page.completed.isEmpty {
                PhoneFoldHeader(model: model, title: "Completed", count: page.completed.count, group: "Completed",
                                in: foldKey, isFolded: completedFolded)
                if !completedFolded {
                    ForEach(page.completed) { PhoneTaskRow(model: model, item: $0) }
                }
            }
            if !page.notes.isEmpty {
                PhoneFoldHeader(model: model, title: "Notes", count: page.notes.count, group: "Notes",
                                in: foldKey, isFolded: model.isFolded("Notes", in: foldKey))
                if !model.isFolded("Notes", in: foldKey) {
                    ForEach(page.notes) { PhoneNoteRow(model: model, note: $0) }
                }
            }
        }
        // Opened from a file's chip or bubble, it brings back the tab bar the file's screen hid, while it's on top.
        .toolbar(nav.stacks[nav.tab]?.last == .tag(path) ? .visible : .automatic, for: .tabBar)
        .onChange(of: tag, initial: true) { if let tag { lastTag = tag } }
        .onAppear { model.showPhoneTagPage(path) }
        .onDisappear {
            // A screen pushed over it leaves its lists kept; popping it lets them go.
            Task {
                if !nav.stacks.values.contains(where: { $0.contains(.tag(path)) }) { model.hidePhoneTagPage(path) }
            }
        }
    }

    private var looseHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: AppModel.Domain.loose.systemImage).foregroundStyle(theme.color(\.accent))
                Text("Loose").scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.strong))
            }
            Hairline()
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// "1 project · 4 open tasks", as the Mac's tag page counts.
    private func subtitle(_ page: TagBrowser, open: Int, untagged: Bool) -> String {
        let areas = page.areasAndProjects.count { $0.properties.kind == .area }
        let projects = page.areasAndProjects.count - areas
        var counts: [String] = []
        if areas > 0 { counts.append(areas == 1 ? "1 area" : "\(areas) areas") }
        if projects > 0 { counts.append(projects == 1 ? "1 project" : "\(projects) projects") }
        counts.append(open == 1 ? "1 open task" : "\(open) open tasks")
        if untagged { counts.insert("No tags", at: 0) }
        return counts.joined(separator: " · ")
    }

    /// A new task carries the tag (none on Untagged) and opens with its title ready to type.
    private func newTask() async {
        model.domain = .tag(path)
        await model.newTask()
        if let path = model.selection { nav.push(.file(path)) }
    }
}

// MARK: A file's Tags row

/// Under the property chips: the file's `tags:` as filled chips, + Tag for the tag sheet, then the body's tags,
/// outlined. A chip opens its tag's screen.
struct PhoneTagChips: View {
    let model: AppModel
    let item: Item
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let written = item.tags.filter(\.inFrontmatter)
        let inText = item.tags.filter { !$0.inFrontmatter }
        WrappingHStack(spacing: 8) {
            ForEach(written, id: \.tag.path) { chip($0.tag, filled: true) }
            Button { nav.sheet = .tags(path: item.path) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").scaledFont(size: 12, weight: .semibold)
                    Text("Tag")
                }
                .foregroundStyle(theme.color(\.muted))
                .padding(.horizontal, 10)
                .scaledMinHeight(34)
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(theme.color(\.border), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Tag")
            ForEach(inText, id: \.tag.path) { chip($0.tag, filled: false) }
        }
        .scaledFont(size: 15)
    }

    private func chip(_ tag: Tag, filled: Bool) -> some View {
        Button { nav.push(.tag(tag.path)) } label: {
            HStack(spacing: 6) {
                Image(systemName: "tag").scaledFont(size: 12, weight: .semibold).foregroundStyle(theme.color(\.accent))
                TagName(tag: tag).foregroundStyle(theme.color(\.strong)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .scaledMinHeight(34)
            .background(filled ? theme.tagFill() : .clear, in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(filled ? theme.tagRing : theme.color(\.border)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tag \(tag.name)")
        .accessibilityValue(filled ? "" : "In the text")
    }
}

// MARK: The tag sheet

/// tagMenu as a sheet: search, In this file (`tags:` ticked, the body's greyed "in text"), All tags with counts, and
/// Create when no tag has the typed path. A tap toggles and the sheet stays open.
struct PhoneTagSheet: View {
    let model: AppModel
    let path: String
    @State private var query = ""
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            List {
                if let item = model.index[path] {
                    let menu = TagChoice.menu(item: item, tree: model.tagTree, query: query)
                    ForEach(menu.sections.indices, id: \.self) { i in
                        Section {
                            ForEach(menu.sections[i].items, id: \.title) { row($0) }
                        } header: {
                            if let label = menu.sections[i].label { Text(label) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color(\.bg))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Add or find a tag")
            .onSubmit(of: .search) {
                if let tag = Tag(query) { pick(.create(tag)) }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(theme.color(\.accent))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ choice: TagChoice) -> some View {
        Button { pick(choice) } label: {
            HStack(spacing: 12) {
                switch choice {
                case let .tag(tag, count, inFile, inText):
                    Image(systemName: "tag").foregroundStyle(theme.color(inText ? \.muted : \.accent))
                    TagName(tag: tag).foregroundStyle(theme.color(inText ? \.muted : \.fg)).lineLimit(1)
                    Spacer()
                    if inFile {
                        Image(systemName: "checkmark").scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.accent))
                    } else if inText {
                        Text("in text").scaledFont(size: 13).foregroundStyle(theme.color(\.muted))
                    } else {
                        Text("\(count)").foregroundStyle(theme.color(\.muted))
                    }
                case .create:
                    Image(systemName: "plus").foregroundStyle(theme.color(\.accent))
                    Text(choice.title).foregroundStyle(theme.color(\.fg))
                    Spacer()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!choice.isPickable)
        .listRowBackground(theme.color(\.code))
        .accessibilityValue(choice.accessibilityValue)
        .accessibilityAddTraits(choice.isInFile ? .isSelected : [])
    }

    private func pick(_ choice: TagChoice) {
        switch choice {
        case .tag(_, _, _, true):
            return
        case let .tag(tag, _, true, _):
            nav.play(.pick)
            Task { await model.removeTag(tag, from: path) }
        case let .tag(tag, _, false, _), let .create(tag):
            nav.play(.pick)
            query = ""
            Task { await model.addTag(tag, to: path) }
        }
    }
}

private extension TagChoice {
    var isInFile: Bool { if case .tag(_, _, true, _) = self { true } else { false } }
}
#endif
