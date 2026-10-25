// The Notes tab: Loose and the folder tree (folding as the Mac's sidebar does), and a folder's screen with its
// subfolders and notes.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneNotesScreen: View {
    let model: AppModel
    @State private var isNamingFolder = false
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let folders = Self.count(model.folderTree)
        PhoneList(model: model, title: "Notes",
                  subtitle: "\(model.index.notes.count == 1 ? "1 note" : "\(model.index.notes.count) notes") · \(folders == 1 ? "1 folder" : "\(folders) folders")",
                  add: { await newNote(in: "") }, addLabel: "New Note") {
            Button("New Folder", systemImage: "folder.badge.plus") { isNamingFolder = true }
        } content: {
            PhoneCard {
                PhoneTreeRow(symbol: "tray", name: "Loose", spoken: Self.spoken("Loose", model.looseNoteCount), route: .folder(""),
                             count: model.looseNoteCount, isLast: true)
            }
            .padding(.top, 10)
            PhoneCardLabel(title: "Folders")
            if model.folderTree.isEmpty {
                Text("No folders yet")
                    .scaledFont(size: 15)
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 32)
            } else {
                let rows = visibleFolders
                PhoneCard {
                    ForEach(rows, id: \.node.id) { row in
                        let node = row.node
                        PhoneTreeRow(symbol: "folder", name: node.name, spoken: Self.spoken(node.name, node.count), route: .folder(node.path),
                                     count: node.count, depth: row.depth, hasChildren: !node.children.isEmpty,
                                     isFolded: model.isFolderFolded(node.path), isLast: node.id == rows.last?.node.id) {
                            model.toggleFolderFolded(node.path)
                        }
                    }
                }
            }
        }
        .newFolderAlert(model: model, in: "", isPresented: $isNamingFolder)
    }

    /// The folder tree's rows, less the folded folders' children.
    private var visibleFolders: [(node: FolderNode, depth: Int)] {
        func rows(_ nodes: [FolderNode], depth: Int) -> [(node: FolderNode, depth: Int)] {
            nodes.flatMap { [($0, depth)] + (model.isFolderFolded($0.path) ? [] : rows($0.children, depth: depth + 1)) }
        }
        return rows(model.folderTree, depth: 0)
    }

    fileprivate static func spoken(_ name: String, _ count: Int) -> String {
        "\(name), \(count == 1 ? "1 note" : "\(count) notes")"
    }

    private static func count(_ nodes: [FolderNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + count($1.children) }
    }

    private func newNote(in folder: String) async {
        model.domain = .folder(folder)
        await model.newNote()
        if let path = model.selection { nav.push(.file(path)) }
    }
}

// MARK: A folder's notes

struct PhoneFolderScreen: View {
    let model: AppModel
    /// `""` for Loose, the top level.
    let path: String
    @State private var isNamingFolder = false
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let notes = model.index.notes(in: path)
        let children = path.isEmpty ? [] : Self.node(path, in: model.folderTree)?.children ?? []
        let name = path.isEmpty ? "Loose" : String(path.split(separator: "/").last ?? "")
        PhoneList(model: model, title: name,
                  subtitle: [notes.count == 1 ? "1 note" : "\(notes.count) notes",
                             children.isEmpty ? nil : children.count == 1 ? "1 folder" : "\(children.count) folders"]
                      .compactMap { $0 }.joined(separator: " · "),
                  icon: AnyView(Image(systemName: path.isEmpty ? "tray" : "folder")
                      .scaledFont(size: 26)
                      .foregroundStyle(theme.color(\.link))),
                  add: newNote, addLabel: "New Note") {
            Button("New Note", systemImage: "plus") { Task { await newNote() } }
            Button("New Folder", systemImage: "folder.badge.plus") { isNamingFolder = true }
        } content: {
            if !children.isEmpty {
                PhoneCard {
                    ForEach(children) { child in
                        PhoneTreeRow(symbol: "folder", name: child.name, spoken: PhoneNotesScreen.spoken(child.name, child.count),
                                     route: .folder(child.path), count: child.count, isLast: child.id == children.last?.id)
                    }
                }
                .padding(.top, 10)
                PhoneCardLabel(title: "Notes")
            }
            ForEach(notes) { PhoneNoteRow(model: model, note: $0) }
            if notes.isEmpty {
                Text(path.isEmpty ? "No notes at the top level." : "No notes in \(name) itself.")
                    .scaledFont(size: 15)
                    .foregroundStyle(theme.color(\.muted))
                    .padding(16)
            }
        }
        .newFolderAlert(model: model, in: path, isPresented: $isNamingFolder)
    }

    private static func node(_ path: String, in nodes: [FolderNode]) -> FolderNode? {
        for node in nodes {
            if node.path == path { return node }
            if path.hasPrefix(node.path + "/"), let found = Self.node(path, in: node.children) { return found }
        }
        return nil
    }

    /// A new note opens in this folder with its title ready to type.
    private func newNote() async {
        model.domain = .folder(path)
        await model.newNote()
        if let path = model.selection { nav.push(.file(path)) }
    }
}

// MARK: Pieces

private struct NewFolderAlert: ViewModifier {
    let model: AppModel
    let parent: String
    @Binding var isPresented: Bool
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("New Folder", isPresented: $isPresented) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { name = "" }
            Button("Create") {
                let name = name.trimmingCharacters(in: .whitespaces)
                self.name = ""
                Task { await name.isEmpty ? model.newFolder(in: parent) : model.newFolder(named: name, in: parent) }
            }
        }
    }
}

private extension View {
    /// Asks for a name, then creates the folder in `parent` (`""` for the top level).
    func newFolderAlert(model: AppModel, in parent: String, isPresented: Binding<Bool>) -> some View {
        modifier(NewFolderAlert(model: model, parent: parent, isPresented: isPresented))
    }
}
#endif
