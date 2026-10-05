// Sidebar: search, the three domains and Trash with counts, active projects with progress rings, the folder line,
// Settings and the New buttons.
import SwiftUI
import TaDaCore

struct SidebarView: View {
    @Bindable var model: AppModel
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
                    row(.today, "Today", systemImage: "star.fill", tint: \.due, count: model.todayCount)
                    row(.upcoming, "Upcoming", systemImage: "calendar", tint: \.deadline, count: nil)
                    row(.loose, "Loose tasks", systemImage: "tray", tint: \.accent, count: model.looseCount)
                    row(.trash, "Trash", systemImage: "trash", tint: \.muted, count: model.trash.count)
                        .padding(.top, 8)

                    Text("Projects")
                        .textCase(.uppercase)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.66)
                        .foregroundStyle(theme.color(\.muted))
                        .padding(.horizontal, 10)
                        .padding(.top, 20)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)

                    if model.projects.isEmpty {
                        Text("No active projects")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.color(\.muted))
                            .padding(.horizontal, 10)
                    }
                    ForEach(model.projects) { progress in
                        projectRow(progress)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            folderLine
            settingsRow
            newButtons
        }
        .background(theme.color(\.side))
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
    }

    private func row(_ domain: AppModel.Domain, _ title: String, systemImage: String,
                     tint: KeyPath<Theme, NSColor>, count: Int?) -> some View {
        SidebarRow(selected: model.domain == domain && !model.isSearching, height: 32, count: count) {
            model.show(domain)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(theme.color(tint))
                .frame(width: 16)
                .accessibilityHidden(true)
        } label: {
            Text(title)
        }
    }

    private func projectRow(_ progress: ProjectProgress) -> some View {
        let path = progress.project.path
        return SidebarRow(selected: model.domain == .project(path) && !model.isSearching, height: 30, count: progress.open) {
            // Clicking the open project again goes from its page back to its tasks.
            if model.domain == .project(path), model.selection == path { model.selection = nil }
            model.show(.project(path))
        } icon: {
            ProgressRing(fraction: progress.fraction)
                .foregroundStyle(theme.color(\.accent))
                .frame(width: 16)
        } label: {
            Text(progress.project.title)
        }
        .accessibilityValue("\(progress.done) of \(progress.total) tasks done")
        .fileMenu(model, path: path)
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
        .help("Search titles, summaries, areas and contexts (⌥⌘F)")
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
            newButton("New task") { await model.newTask() }
            newButton("New project") { await model.newProject() }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private func newButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: "plus")
                .font(.system(size: 12))
                .foregroundStyle(theme.color(\.fg))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
