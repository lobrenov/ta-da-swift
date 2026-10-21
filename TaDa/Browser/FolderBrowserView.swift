// A notes folder's page beside the document pane, or Loose's: its icon and name (the parent path muted, the name
// renamed in place), a count line, its subfolders as chips, the tag filter, its own notes by title, then "New note in <folder>".
#if os(macOS)
import SwiftUI
import TaDaCore

struct FolderBrowserView: View {
    let model: AppModel
    /// `""` for Loose, the top level.
    let folder: String
    @Environment(\.theme) private var theme

    var body: some View {
        let all = model.index.notes(in: folder)
        let filter = model.tagFilter(on: .folder(folder))
        let notes = filter.apply(all)
        let children = folder.isEmpty ? [] : Self.node(folder, in: model.folderTree)?.children ?? []
        BrowserColumn(model: model, paths: notes.map(\.path), spacing: 1) {
            header(notes: all, shown: notes.count, children: children)
        } content: {
            ForEach(notes) { note in
                NoteRow(item: note, selected: model.isSelected(note.path)) { model.click(note.path) }
                    .fileMenu(model, path: note.path)
                    .draggable(containerItemID: note.path)
            }
            if notes.isEmpty, filter.isActive {
                Text("No note here carries the picked tags.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            } else if notes.isEmpty {
                Text(folder.isEmpty ? "No notes at the top level." : "No notes in \(name) itself.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            Button { Task { await model.newNote() } } label: {
                Label("New note in \(name)", systemImage: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }

    private var name: String { folder.isEmpty ? "Loose" : String(folder.split(separator: "/").last ?? "") }

    private func header(notes: [Item], shown: Int, children: [FolderNode]) -> some View {
        let parent = Vault.folder(of: folder)
        var counts = [notes.count == 1 ? "1 note" : "\(notes.count) notes"]
        if !children.isEmpty { counts.append(children.count == 1 ? "1 folder" : "\(children.count) folders") }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: folder.isEmpty ? "tray" : "folder")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.color(\.link))
                    .accessibilityHidden(true)
                if !parent.isEmpty {
                    Text(parent + "/")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(theme.color(\.muted))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if folder.isEmpty {
                    Text("Loose")
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.24)
                        .foregroundStyle(theme.color(\.strong))
                        .accessibilityAddTraits(.isHeader)
                } else {
                    InlineTitleField(model: model, path: folder, height: 34, font: .system(size: 24, weight: .bold),
                                     focus: nil, rename: { await model.renameFolder(folder, to: $0) }) {
                        Text(name)
                            .tracking(-0.24)
                            .foregroundStyle(theme.color(\.strong))
                            .accessibilityAddTraits(.isHeader)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(height: 34)
            Text(counts.joined(separator: " · "))
                .font(.system(size: 11.5))
                .foregroundStyle(theme.color(\.muted))
            if !children.isEmpty {
                WrappingHStack(spacing: 6) {
                    ForEach(children) { child in
                        Button { model.show(.folder(child.path)) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "folder")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(theme.color(\.link))
                                Text(child.name).foregroundStyle(theme.color(\.fg))
                                Text("\(child.count)").monospacedDigit().foregroundStyle(theme.color(\.muted))
                            }
                            .font(.system(size: 12))
                            .padding(.leading, 8)
                            .padding(.trailing, 10)
                            .frame(height: 24)
                            .background(theme.color(\.code), in: .capsule)
                            .overlay(Capsule().strokeBorder(theme.color(\.border)))
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Folder \(child.name), \(child.count == 1 ? "1 note" : "\(child.count) notes")")
                    }
                }
            }
            TagFilterRow(model: model, domain: .folder(folder), items: notes, shown: (shown, notes.count))
        }
    }

    /// The tree's node for `path`.
    static func node(_ path: String, in nodes: [FolderNode]) -> FolderNode? {
        for node in nodes {
            if node.path == path { return node }
            if path.hasPrefix(node.path + "/") { return self.node(path, in: node.children) }
        }
        return nil
    }
}
#endif
