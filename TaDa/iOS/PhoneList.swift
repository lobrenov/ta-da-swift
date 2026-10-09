// What every tab's list shares: the title and subtitle, pull to search and its field, the floating +, picking rows,
// and search results.
#if os(iOS)
import SwiftUI
import TaDaCore

/// How far past the top a list is pulled for search to open when the finger lifts.
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
    @State private var isSearchOpen = false
    @FocusState private var isSearchFocused: Bool
    @State private var pull = SearchPull()
    @State private var isDragging = false
    /// The title has scrolled under the navigation bar, which then shows it.
    @State private var isTitleScrolledAway = false
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !isSearchOpen {
                        header.transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity.animation(.easeIn(duration: 0.2).delay(0.12))),
                            removal: .move(edge: .top).combined(with: .opacity.animation(.easeOut(duration: 0.12)))))
                    }
                    if isSearching {
                        PhoneSearchResults(model: model, query: query)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) { content }
                            .padding(.bottom, 96)
                    }
                }
            }
            .onChange(of: scrollTarget) {
                if let scrollTarget { withAnimation { proxy.scrollTo(scrollTarget, anchor: .top) } }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                pull.distance = max(0, -offset)
                isTitleScrolledAway = offset > 44
                guard isDragging, !isSearchOpen else { return }
                let isArmed = pull.distance >= searchPullThreshold
                if isArmed, !pull.isArmed { nav.play(.press) }
                pull.isArmed = isArmed
            }
            .onScrollPhaseChange { _, phase in
                isDragging = phase == .interacting
                if !isDragging, pull.isArmed, !isSearchOpen { openSearch() }
            }
            .overlay {
                if isSearchOpen, !isSearching {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { closeSearch() }
                }
            }
            .overlay(alignment: .top) {
                PullSearchField(pull: pull, isOpen: isSearchOpen, query: $query, isFocused: $isSearchFocused,
                                close: closeSearch)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.color(\.bg))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            if let add, !nav.isPicking, !isSearching {
                FloatingAddButton { Task { await add() } }
            }
        }
        .toolbar {
            if !nav.isPicking {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(theme.color(\.strong))
                        .opacity(isTitleScrolledAway && !isSearchOpen ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: isTitleScrolledAway)
                }
                if !isSearchOpen {
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
        }
        .pickingBars(model: model)
        .onAppear { nav.pickable = pickable }
        .onChange(of: pickable) { nav.pickable = pickable }
    }

    /// The large title and subtitle, at the top of the list.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(theme.color(\.strong))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.color(\.muted))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func openSearch() {
        withAnimation(PullSearchField.morph) { isSearchOpen = true }
        isSearchFocused = true
    }

    private func closeSearch() {
        pull.isArmed = false
        query = ""
        isSearchFocused = false
        withAnimation(PullSearchField.morph) { isSearchOpen = false }
    }
}

/// How far a list is pulled past its top, and whether lifting the finger there opens search.
@Observable
private final class SearchPull {
    var distance: CGFloat = 0
    /// Pulled past `searchPullThreshold` while the finger is down; stays set while search is open.
    var isArmed = false
}

/// Pull to search, drawn over the list. In the gap a pull opens above the title, a pill stretches with the pull and
/// snaps into an accent dot at the threshold; on release the dot grows into the search field in the navigation bar's
/// row, with a close button where the "…" was.
private struct PullSearchField: View {
    let pull: SearchPull
    let isOpen: Bool
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding
    let close: () -> Void
    @Environment(\.theme) private var theme

    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.84)
    /// The navigation bar's row, above the list's top.
    private static let barRow: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let isDot = pull.isArmed && !isOpen
            // At rest it waits as a dot in the bar's row, so closing shrinks the field in place.
            let isResting = !isOpen && !isDot && pull.distance == 0
            let size = isOpen ? CGSize(width: width - 16 * 2 - 44 - 8, height: 40)
                : isDot || isResting ? CGSize(width: 40, height: 40)
                : CGSize(width: 36, height: max(36, pull.distance - 12))
            let center = isOpen ? CGPoint(x: 16 + size.width / 2, y: -Self.barRow / 2)
                : isResting ? CGPoint(x: width / 2, y: -Self.barRow / 2)
                : isDot ? CGPoint(x: width / 2, y: pull.distance / 2)
                : CGPoint(x: width / 2, y: 6 + size.height / 2)
            ZStack {
                field(size: size, isDot: isDot)
                    .position(center)
                    .opacity(isOpen ? 1 : min(1, pull.distance / 28))
                    .animation(.spring(response: 0.3, dampingFraction: 0.55), value: pull.isArmed)
                Button("Cancel", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .foregroundStyle(theme.color(\.strong))
                    .position(x: width - 16 - 22, y: -Self.barRow / 2)
                    .opacity(isOpen ? 1 : 0)
                    .scaleEffect(isOpen ? 1 : 0.6)
                    .allowsHitTesting(isOpen)
            }
        }
    }

    private func field(size: CGSize, isDot: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.color(isDot ? \.bg : \.muted))
                .accessibilityHidden(true)
            if isOpen {
                TextField("Search", text: $query)
                    .focused(isFocused)
                    .submitLabel(.search)
                    .font(.system(size: 17))
                    .foregroundStyle(theme.color(\.fg))
                    .transition(.opacity)
                if !query.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(theme.color(\.muted))
                }
            }
        }
        .padding(.horizontal, isOpen ? 12 : 0)
        .padding(.bottom, isOpen || isDot ? 0 : 9)
        .frame(width: size.width, height: size.height,
               alignment: isOpen ? .leading : isDot ? .center : .bottom)
        .background(isDot ? theme.color(\.accent) : theme.color(\.surface).opacity(0.5), in: .capsule)
        .overlay {
            Circle()
                .strokeBorder(theme.color(\.accent), lineWidth: 2)
                .keyframeAnimator(initialValue: 0.0, trigger: pull.isArmed) { ring, phase in
                    ring.scaleEffect(1 + (1 - phase) * 0.9).opacity(isDot ? phase * 0.6 : 0)
                } keyframes: { _ in
                    LinearKeyframe(1.0, duration: 0)
                    LinearKeyframe(0.0, duration: 0.38)
                }
                .frame(width: 40, height: 40)
                .allowsHitTesting(false)
        }
        .allowsHitTesting(isOpen)
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
