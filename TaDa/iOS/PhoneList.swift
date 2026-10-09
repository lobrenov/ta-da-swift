// What every tab's list shares: the large title and subtitle, the search field a pull down reveals (and, pulled
// further, focuses), the floating +, picking rows, and search results.
#if os(iOS)
import SwiftUI
import TaDaCore

/// How far past the top a list is pulled for its search field to take the keyboard when the finger lifts.
private let searchPullThreshold: CGFloat = 60

/// A tab's list. `pickable` are its rows top to bottom, for picking; `add` is the floating +.
struct PhoneList<Content: View, MenuItems: View>: View {
    let model: AppModel
    let title: String
    var subtitle = ""
    var pickable: [String] = []
    var add: (() async -> Void)? = nil
    /// A row id to scroll to the top, as Upcoming's week strip asks.
    var scrollTarget: String? = nil
    @ViewBuilder var menu: MenuItems
    @ViewBuilder var content: Content
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    /// The list is pulled past `searchPullThreshold` while the finger is down.
    @State private var isPulledToSearch = false
    @State private var isDragging = false
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isSearching {
                    PhoneSearchResults(model: model, query: query)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) { content }
                        .padding(.bottom, 96)
                }
            }
            .onChange(of: scrollTarget) {
                if let scrollTarget { withAnimation { proxy.scrollTo(scrollTarget, anchor: .top) } }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y < -geometry.contentInsets.top - searchPullThreshold
            } action: { _, isPulled in
                if isDragging { isPulledToSearch = isPulled }
            }
            .onScrollPhaseChange { _, phase in
                isDragging = phase == .interacting
                if !isDragging, isPulledToSearch {
                    isPulledToSearch = false
                    nav.play(.press)
                    isSearchFocused = true
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.color(\.bg))
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
        .searchFocused($isSearchFocused)
        .overlay(alignment: .bottomTrailing) {
            if let add, !nav.isPicking, !isSearching {
                FloatingAddButton { Task { await add() } }
            }
        }
        .toolbar {
            if !nav.isPicking {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        menu
                        if !pickable.isEmpty {
                            Button("Select", systemImage: "checkmark.circle") { nav.startPicking() }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
        }
        .pickingBars(model: model)
        .onAppear { nav.pickable = pickable }
        .onChange(of: pickable) { nav.pickable = pickable }
    }
}

/// The accent + at a list's bottom right that makes a new file.
struct FloatingAddButton: View {
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
        .accessibilityLabel("New Task")
        .padding(.trailing, 20)
        .padding(.bottom, 12)
    }
}

/// "All" and one pill per context; picking one filters the list.
struct PhoneContextPills: View {
    let contexts: [String]
    @Binding var selection: String?
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                pill("All", nil)
                ForEach(contexts, id: \.self) { pill($0, $0) }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.never)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by context")
    }

    private func pill(_ label: String, _ value: String?) -> some View {
        let on = selection == value
        return Button { selection = value } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.color(on ? \.strong : \.fg))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(on ? theme.color(\.surface) : .clear, in: .capsule)
                .overlay { if !on { Capsule().strokeBorder(theme.color(\.border)) } }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
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
        LazyVStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                ContentUnavailableView.search(text: query).padding(.top, 60)
            }
            if !projects.isEmpty {
                PhoneSectionHeader(title: "Projects")
                ForEach(projects) { project in
                    Button { nav.push(.project(project.path)) } label: {
                        HStack(spacing: 12) {
                            ProgressRing(fraction: model.index.progress(of: project).fraction)
                                .scaleEffect(22 / 14)
                                .foregroundStyle(theme.color(\.accent))
                                .frame(width: 24)
                            Text(highlighted(project.title, words))
                                .font(.system(size: 17))
                                .foregroundStyle(theme.color(\.fg))
                            Spacer()
                            Text("\(model.index.tasks(in: project).count) tasks")
                                .font(.system(size: 15))
                                .foregroundStyle(theme.color(\.muted))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    PhoneRowSeparator(inset: 52)
                }
            }
            if !tasks.isEmpty {
                PhoneSectionHeader(title: "Tasks", count: tasks.count)
                ForEach(tasks) { task in
                    PhoneTaskRow(model: model, item: task, search: (words, place(of: task)))
                }
            }
        }
        .padding(.bottom, 96)
    }

    private func place(of task: Item) -> String {
        var parts = [model.index.project(of: task)?.title ?? "Loose task"]
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
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.color(\.strong))
                Spacer()
                if let count { Text("\(count)").font(.system(size: 15)).foregroundStyle(theme.color(\.muted)) }
            }
            Hairline()
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The rule under a row, inset to line up with its title.
struct PhoneRowSeparator: View {
    var inset: CGFloat = 50

    var body: some View {
        Hairline().padding(.leading, inset)
    }
}
#endif
