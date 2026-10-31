// What every tab's list shares: the title and subtitle, pull to search, the floating +, picking rows, and search
// results.
#if os(iOS)
import SwiftUI
import TaDaCore

/// A tab's list. `pickable` are its rows top to bottom, for picking; `add` is the floating +.
struct PhoneList<Content: View, MenuItems: View>: View {
    let model: AppModel
    let title: String
    var subtitle = ""
    /// Before the large title, as an area's cube.
    var icon: AnyView? = nil
    /// At the large title's end, as the Group menu.
    var titleAccessory: AnyView? = nil
    /// A top-bar button before More that opens the page's own file, with its label.
    var fileButton: (label: String, open: () -> Void)? = nil
    var pickable: [String] = []
    var add: (() async -> Void)? = nil
    var addLabel = "New Task"
    /// The picking bar's content instead of the file actions, as the Attachments list's Move to Trash.
    var pickingActions: AnyView? = nil
    /// What typing in search shows instead of the files that match.
    var searchResults: ((String) -> AnyView)? = nil
    @ViewBuilder var menu: MenuItems
    @ViewBuilder var content: Content
    @State private var search = ListSearch()
    /// On screen: not in another tab, nor under a pushed screen. Only the list on screen sets what can be picked.
    @State private var isOnScreen = false
    /// The title has scrolled under the navigation bar, which then shows it.
    @State private var isTitleScrolledAway = false
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !search.isOpen {
                    header.transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.2).delay(0.12))),
                        removal: .opacity.animation(.linear(duration: 0.05))))
                }
                if search.isSearching {
                    if let searchResults { searchResults(search.query) } else { PhoneSearchResults(model: model, query: search.query) }
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        content
                        PickingBarClearance()
                    }
                }
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 44
        } action: { _, isScrolledAway in
            isTitleScrolledAway = isScrolledAway
        }
        .pullToSearch(search)
        .scrollDismissesKeyboard(.interactively)
        .background { theme.color(\.bg).ignoresSafeArea() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            if let add, !nav.isPicking, !search.isSearching {
                FloatingAddButton(label: addLabel) { Task { await add() } }
            }
        }
        .toolbar {
            if !nav.isPicking {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(theme.color(\.strong))
                        .opacity(isTitleScrolledAway && !search.isOpen ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: isTitleScrolledAway)
                }
                if !search.isOpen, let fileButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(fileButton.label, systemImage: "doc.text", action: fileButton.open)
                    }
                }
                if !search.isOpen {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            menu
                            Button("Search", systemImage: "magnifyingglass") { search.open() }
                            if !pickable.isEmpty {
                                Button("Select", systemImage: "checkmark.circle") { nav.startPicking() }
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                    }
                }
            }
        }
        .pickingBars(model: model, actions: pickingActions)
        .navigationBarBackButtonHidden(search.isOpen || nav.isPicking)
        .onAppear {
            isOnScreen = true
            nav.setPickable(pickable)
        }
        .onDisappear { isOnScreen = false }
        .onChange(of: pickable) { if isOnScreen { nav.setPickable(pickable) } }
    }

    /// The large title and subtitle, at the top of the list, and the title's accessory.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    if let icon { icon }
                    Text(title)
                        .scaledFont(size: 34, weight: .bold)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(theme.color(\.strong))
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .scaledFont(size: 13)
                        .foregroundStyle(theme.color(\.muted))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let titleAccessory {
                Spacer(minLength: 0)
                titleAccessory.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// The accent + at a list's bottom right that makes a new file.
struct FloatingAddButton: View {
    var label = "New Task"
    let action: () -> Void
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            nav.play(.press)
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(theme.color(\.accent))
        .accessibilityLabel(label)
        .padding(.trailing, 20)
        .padding(.bottom, 12)
    }
}

/// Files matching every word of `query`: projects first, then tasks, each with the line that matched.
struct PhoneSearchResults: View {
    let model: AppModel
    let query: String
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let results = model.index.search(query)
        let projects = results.filter { $0.properties.kind == .project }
        let tasks = results.filter { $0.properties.kind == .task }
        let notes = results.filter { $0.properties.kind == .note }
        LazyVStack(alignment: .leading, spacing: 0) {
            if projects.isEmpty, tasks.isEmpty, notes.isEmpty {
                ContentUnavailableView.search(text: query).padding(.top, 60)
            }
            if !projects.isEmpty {
                PhoneSectionHeader(title: "Projects")
                ForEach(projects) { project in
                    Button { nav.push(.project(project.path)) } label: {
                        HStack(spacing: 12) {
                            ProgressRing(model.index.progress(of: project))
                                .scaleEffect(22 / 14)
                                .foregroundStyle(theme.color(\.accent))
                                .frame(width: 24)
                            Text(highlighted(project.title, words))
                                .scaledFont(size: 17)
                                .foregroundStyle(theme.color(\.fg))
                            Spacer()
                            Text("\(model.index.tasks(in: project).count) tasks")
                                .scaledFont(size: 15)
                                .foregroundStyle(theme.color(\.muted))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !tasks.isEmpty {
                PhoneSectionHeader(title: "Tasks", count: tasks.count)
                ForEach(tasks) { task in
                    PhoneTaskRow(model: model, item: task, search: (words, place(of: task)))
                }
            }
            if !notes.isEmpty {
                PhoneSectionHeader(title: "Notes", count: notes.count)
                ForEach(notes) { PhoneNoteRow(model: model, note: $0) }
            }
            PickingBarClearance()
        }
        .environment(\.swipesToPick, false)
    }

    private func place(of task: Item) -> String {
        var parts = [model.index.parent(of: task)?.title ?? "Loose task"]
        let p = task.properties
        if let due = p.dueDate { parts.append("Due \(due.relativeLabel(today: model.today))") }
        if let deadline = p.deadline { parts.append("Deadline \(deadline.relativeLabel(today: model.today))") }
        return parts.joined(separator: " · ")
    }

    private func highlighted(_ text: String, _ words: [String]) -> AttributedString {
        text.highlighting(words, fill: theme.color(\.due).opacity(theme.isDark ? 0.3 : 0.25))
    }
}

extension String {
    /// The text with each occurrence of `words` on `fill`, ignoring case and diacritics.
    func highlighting(_ words: [String], fill: Color) -> AttributedString {
        var result = AttributedString(self)
        for word in words where !word.isEmpty {
            var searchRange = startIndex..<endIndex
            while let found = range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                if let lower = AttributedString.Index(found.lowerBound, within: result),
                   let upper = AttributedString.Index(found.upperBound, within: result) {
                    result[lower..<upper].backgroundColor = fill
                }
                searchRange = found.upperBound..<endIndex
            }
        }
        return result
    }
}

/// A group's semibold title, with an optional count on the right, over a rule.
struct PhoneSectionHeader: View {
    let title: String
    var count: Int? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).scaledFont(size: 17, weight: .semibold).foregroundStyle(theme.color(\.strong))
                Spacer()
                if let count { Text("\(count)").scaledFont(size: 15).foregroundStyle(theme.color(\.muted)) }
            }
            Hairline()
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
#endif
