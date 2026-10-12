// Sidebar: search, Today and Upcoming, Logbook, Trash with its count, then the Projects | Tags switch. Projects lists
// Loose tasks, active projects without an area, then each area with its active projects under it; Tags lists Untagged
// and the tag tree. Then the folder line, Settings and the New buttons. Task rows drop onto Today, Loose tasks, the
// projects and the areas; project rows drop onto the areas.
import SwiftUI
import TaDaCore

#if os(macOS)
struct SidebarView: View {
    @Bindable var model: AppModel
    /// Search Files focuses this sidebar's search field; a hidden sidebar's it doesn't.
    var takesSearchFocus = true
    /// The search field has the keyboard as the sidebar appears.
    var focusesSearch = false
    /// A domain, area or project was picked, the open one included.
    var picked: () -> Void = {}
    @Environment(\.theme) private var theme
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    row(.today, count: model.todayCount)
                        .taskDrop(model, onto: .today)
                    row(.upcoming, count: nil)
                    row(.logbook, count: nil)
                        .padding(.top, 8)
                    row(.trash, count: model.trashCount)

                    SidebarModeSwitch(mode: $model.sidebarMode)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                    switch model.sidebarMode {
                    case .projects: hierarchy
                    case .tags: tags
                    case .notes: EmptyView()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .taskDragContainer(model)
            }
            folderLine
            settingsRow
            newButtons
        }
        .background(theme.color(\.side))
        .onChange(of: model.searchFocusRequest) { if takesSearchFocus { searchFocused = true } }
        .onAppear { if focusesSearch { searchFocused = true } }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
    }

    /// Loose tasks, the active projects without an area, then each area with its active projects.
    @ViewBuilder private var hierarchy: some View {
        row(.loose, count: model.looseCount, title: "Loose")
            .taskDrop(model, onto: .loose)
        if model.looseProjects.isEmpty, model.areas.isEmpty {
            Text("No active projects")
                .font(.system(size: 12))
                .foregroundStyle(theme.color(\.muted))
                .padding(.horizontal, 10)
                .padding(.top, 12)
        }
        if !model.looseProjects.isEmpty { Spacer().frame(height: 12) }
        ForEach(model.looseProjects) { progress in
            projectRow(progress)
        }
        ForEach(model.areas) { area in
            areaRow(area.area)
                .padding(.top, 12)
            ForEach(area.projects) { progress in
                projectRow(progress)
            }
        }
    }

    /// Untagged, then the tag tree: roots aligned with Untagged, 16pt per level, the last segment only, a parent folding from its chevron.
    @ViewBuilder private var tags: some View {
        row(.tag(nil), count: model.untaggedCount)
        Spacer().frame(height: 10)
        if model.tagTree.isEmpty {
            Text("No tags yet")
                .font(.system(size: 12))
                .foregroundStyle(theme.color(\.muted))
                .padding(.horizontal, 10)
        }
        ForEach(model.visibleTags, id: \.node.id) { entry in
            tagRow(entry.node, depth: entry.depth)
        }
    }

    /// A tag: a row with its glyph, last segment and count, and for a parent a fold chevron in the row's leading padding.
    private func tagRow(_ node: TagNode, depth: Int) -> some View {
        let path = node.tag.path
        let folded = model.isTagFolded(path)
        return SidebarRow(selected: model.domain == .tag(path) && !model.isSearching, height: 30, count: node.count) {
            model.show(.tag(path))
            picked()
        } icon: {
            Image(systemName: "tag")
                .font(.system(size: 11))
                .foregroundStyle(theme.color(\.accent))
                .frame(width: 16)
                .accessibilityHidden(true)
        } label: {
            Text(node.tag.leaf)
        }
        .accessibilityLabel("Tag \(node.tag.name)")
        .overlay(alignment: .leading) {
            if !node.children.isEmpty {
                Button { model.toggleTagFolded(path) } label: {
                    Image(systemName: folded ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.color(\.muted))
                        .frame(width: 10, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(folded ? "Expand \(node.tag.name)" : "Collapse \(node.tag.name)")
            }
        }
        .padding(.leading, CGFloat(depth) * 16)
    }

    private func row(_ domain: AppModel.Domain, count: Int?, title: String? = nil) -> some View {
        SidebarRow(selected: model.domain == domain && !model.isSearching, height: 32, count: count) {
            model.show(domain)
            picked()
        } icon: {
            Image(systemName: domain.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(theme.color(domain.tint))
                .frame(width: 16)
                .accessibilityHidden(true)
        } label: {
            Text(title ?? domain.title)
        }
    }

    /// An area: its cube and title, no count. Clicking the open area again goes from its file back to its page.
    private func areaRow(_ area: Item) -> some View {
        let path = area.path
        return SidebarRow(selected: model.domain == .area(path) && !model.isSearching, height: 32, count: nil) {
            if model.domain == .area(path), model.selection == path { model.selection = nil }
            model.show(.area(path))
            picked()
        } icon: {
            AreaIcon()
        } label: {
            Text(area.title).fontWeight(.semibold).foregroundStyle(theme.color(\.strong))
        }
        .fileMenu(model, path: path)
        .taskDrop(model, onto: .area(area))
    }

    private func projectRow(_ progress: ProjectProgress) -> some View {
        let path = progress.project.path
        return SidebarRow(selected: model.domain == .project(path) && !model.isSearching, height: 30, count: progress.open) {
            // Clicking the open project again goes from its page back to its tasks.
            if model.domain == .project(path), model.selection == path { model.selection = nil }
            model.show(.project(path))
            picked()
        } icon: {
            ProgressRing(fraction: progress.fraction)
                .foregroundStyle(theme.color(\.accent))
                .frame(width: 16)
        } label: {
            Text(progress.project.title)
        }
        .accessibilityValue("\(progress.done) of \(progress.total) tasks done")
        .fileMenu(model, path: path)
        .taskDrop(model, onto: .project(progress.project))
        .draggable(containerItemID: path)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(theme.color(\.muted))
                .accessibilityHidden(true)
            TextField("Search files", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.color(\.fg))
                .focused($searchFocused)
                .onExitCommand { model.searchText = "" }
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.color(\.muted))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(theme.color(\.surface), in: .rect(cornerRadius: 7))
        .help("Search titles, summaries and areas (⌥⌘F)")
    }

    /// The folder, and whether Ta Da is watching it for changes made by other apps.
    private var folderLine: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isInICloud ? "icloud" : "folder")
                .foregroundStyle(theme.color(model.isWatching ? \.done : \.muted))
                .accessibilityHidden(true)
            Text("\(model.isWatching ? "Watching" : "Not watching") · \(model.folderDisplayName)")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.color(\.muted))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .help(model.isWatching
            ? "Changes made in other apps show up within a few seconds.\n\(model.vault?.root.path(percentEncoded: false) ?? "")"
            : "Ta Da can’t watch this folder, so it checks for changes when you switch back to it.")
    }

    private var settingsRow: some View {
        SidebarRow(selected: false, height: 32, count: nil) {
            openSettings()
        } icon: {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundStyle(theme.color(\.muted))
                .frame(width: 16)
                .accessibilityHidden(true)
        } label: {
            HStack {
                Text("Settings")
                Spacer()
                Text("⌘,")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var newButtons: some View {
        HStack(spacing: 6) {
            newButton("Task", label: "New task") { await model.newTask() }
            newButton("Project", label: "New project") { await model.newProject() }
            newButton("Area", label: "New area") { await model.newArea() }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private func newButton(_ title: String, label: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: "plus")
        }
        .buttonStyle(ActionButtonStyle(height: 32, fullWidth: true))
        .accessibilityLabel(label)
    }
}

/// The Projects | Tags switch: two segments on a `surface` track, the picked one on `bg` in semibold `strong`.
private struct SidebarModeSwitch: View {
    @Binding var mode: AppModel.SidebarMode
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            segment(.projects, "Projects") { AreaIcon(size: 13) }
            segment(.tags, "Tags") {
                Image(systemName: "tag").font(.system(size: 11)).foregroundStyle(theme.color(\.accent))
            }
        }
        .padding(2)
        .background(theme.color(\.surface), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar lists")
    }

    private func segment(_ value: AppModel.SidebarMode, _ title: String, @ViewBuilder icon: () -> some View) -> some View {
        let selected = mode == value
        return Button { mode = value } label: {
            HStack(spacing: 6) {
                icon()
                Text(title)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(theme.color(selected ? \.strong : \.fg))
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(selected ? theme.color(\.bg) : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("\(title) (swipe sideways over the sidebar)")
    }
}

/// One selectable sidebar row: icon, label, optional count; selected rows sit on the surface colour.
struct SidebarRow<Icon: View, Label: View>: View {
    let selected: Bool
    let height: CGFloat
    let count: Int?
    let action: () -> Void
    @ViewBuilder let icon: Icon
    @ViewBuilder let label: Label
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                label
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.color(\.muted))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 13, weight: selected ? .semibold : .medium))
            .foregroundStyle(theme.color(selected ? \.strong : \.fg))
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(selected ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#endif

/// A ring with a pie inside that fills clockwise from the top: done/total of a project's tasks.
struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 1.4)
            Pie(fraction: fraction)
        }
        .frame(width: 12, height: 12)
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }

    nonisolated private struct Pie: Shape {
        let fraction: Double

        func path(in rect: CGRect) -> Path {
            guard fraction > 0 else { return Path() }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            var path = Path()
            path.move(to: center)
            path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                        startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * min(fraction, 1)), clockwise: false)
            path.closeSubpath()
            return path
        }
    }
}
