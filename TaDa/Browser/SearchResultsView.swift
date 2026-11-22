// Search matches in the browser column: tasks and notes as rows, projects with their rings, areas with their cubes, then
// folders. Titles that match come first.
#if os(macOS)
import SwiftUI
import TaDaCore

struct SearchResultsView: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let results = model.index.search(model.searchText)
        let folders = FolderNode.search(model.searchText, in: model.folderTree)
        let count = results.count + folders.count
        // Tasks and notes only: picking a project, area or folder leaves the search for its page.
        BrowserColumn(model: model, paths: results.filter { [.task, .note].contains($0.properties.kind) }.map(\.path), spacing: 1,
                      empty: count == 0 ? noMatches : nil) {
            DomainHeader(title: "Search", systemImage: "magnifyingglass", tint: \.muted) {
                Text("\(count) match\(count == 1 ? "" : "es")")
            }
        } content: {
            ForEach(results) { item in
                Group {
                    if item.properties.kind == .project {
                        pageRow(item.title, hint: "Opens the project", open: { model.open(item.path) }) {
                            ProgressRing(model.index.progress(of: item)).foregroundStyle(theme.color(\.accent))
                        } line: {
                            Text("Project")
                            StatusLabel(status: item.properties.status)
                        }
                    } else if item.properties.kind == .area {
                        pageRow(item.title, hint: "Opens the area", open: { model.open(item.path) }) {
                            AreaIcon()
                        } line: {
                            Text("Area")
                        }
                    } else if item.properties.kind == .note {
                        NoteRow(item: item, selected: model.isSelected(item.path), showsFolder: true) { model.click(item.path) }
                    } else {
                        TaskRow(item: item, selected: model.isSelected(item.path), today: model.today,
                                move: model.index.repeatMove(of: item, today: model.today),
                                onToggle: { Task { await model.toggleCompletion(item) } },
                                onSelect: { model.click(item.path) })
                        .taskDrag(model, path: item.path)
                    }
                }
                .fileMenu(model, path: item.path)
            }
            ForEach(folders) { folder in
                pageRow(folder.name, hint: "Opens the folder", open: { model.show(.folder(folder.path)) }) {
                    Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(theme.color(\.link))
                } line: {
                    Text(Vault.folder(of: folder.path).isEmpty ? "Folder" : "Folder in \(Vault.folder(of: folder.path))")
                    Text(folder.count == 1 ? "1 note" : "\(folder.count) notes")
                }
            }
        }
    }

    private var noMatches: EmptyState {
        EmptyState(systemImage: "magnifyingglass", title: "No results for “\(model.searchText)”")
    }

    /// A project, area or folder: its icon, its name over a muted `line`; a click leaves the search for its page.
    private func pageRow(_ title: String, hint: String, open: @escaping () -> Void, @ViewBuilder icon: () -> some View,
                         @ViewBuilder line: () -> some View) -> some View {
        Button {
            model.searchText = ""
            open()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                icon()
                    .frame(width: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(theme.color(\.fg))
                    HStack(spacing: 12, content: line)
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
        .accessibilityHint(hint)
    }
}
#endif
