// Search matches in the browser column: tasks as rows, projects with their rings. Titles that match come first.
import SwiftUI
import TaDaCore

struct SearchResultsView: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let results = model.index.search(model.searchText)
        // Tasks only: picking a project leaves the search for its page.
        BrowserColumn(model: model, paths: results.filter { $0.properties.kind == .task }.map(\.path), spacing: 1,
                      empty: results.isEmpty ? noMatches : nil) {
            DomainHeader(title: "Search", systemImage: "magnifyingglass", tint: \.muted) {
                Text("\(results.count) match\(results.count == 1 ? "" : "es")")
            }
        } content: {
            ForEach(results) { item in
                Group {
                    if item.properties.kind == .project {
                        projectRow(item)
                    } else {
                        TaskRow(item: item, selected: model.isSelected(item.path), today: model.today,
                                onToggle: { Task { await model.toggleCompletion(item) } },
                                onSelect: { model.click(item.path) })
                        .taskDrag(model, path: item.path)
                    }
                }
                .fileMenu(model, path: item.path)
            }
        }
    }

    private var noMatches: EmptyState {
        EmptyState(systemImage: "magnifyingglass", title: "No matches",
                   message: "No task or project has every word of “\(model.searchText)” in its title, summary, area or contexts.")
    }

    private func projectRow(_ project: Item) -> some View {
        Button {
            model.searchText = ""
            model.open(project.path)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ProgressRing(fraction: model.index.progress(of: project).fraction)
                    .foregroundStyle(theme.color(\.accent))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(theme.color(\.fg))
                    HStack(spacing: 12) {
                        Text("Project")
                        StatusLabel(status: project.properties.status)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the project")
    }
}
