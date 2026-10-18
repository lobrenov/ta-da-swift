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
            FolderCard {
                PhoneFolderRow(model: model, symbol: "tray", name: "Loose", path: "", count: model.looseNoteCount, isLast: true)
            }
            .padding(.top, 10)
            PhoneFolderLabel(title: "Folders")
            if model.folderTree.isEmpty {
                Text("No folders yet")
                    .scaledFont(size: 15)
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 32)
            } else {
                let rows = visibleFolders
                FolderCard {
                    ForEach(rows.indices, id: \.self) { i in
                        PhoneFolderRow(model: model, symbol: "folder", name: rows[i].node.name, path: rows[i].node.path,
                                       count: rows[i].node.count, depth: rows[i].depth, hasChildren: !rows[i].node.children.isEmpty,
                                       isLast: i == rows.count - 1)
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
                FolderCard {
                    ForEach(children) { child in
                        PhoneFolderRow(model: model, symbol: "folder", name: child.name, path: child.path, count: child.count,
                                       isLast: child.id == children.last?.id)
                    }
                }
                .padding(.top, 10)
                PhoneFolderLabel(title: "Notes")
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

/// A group's small muted label above its card.
private struct PhoneFolderLabel: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .scaledFont(size: 13)
            .foregroundStyle(theme.color(\.muted))
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 7)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rows on a rounded `side` card with a hairline border.
private struct FolderCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) { content }
            .background(theme.color(\.side))
            .clipShape(.rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.color(\.border)) }
            .padding(.horizontal, 16)
    }
}

/// A folder or Loose: its icon, name and count, opening its screen. With a `depth` it sits in the tree, indented 28pt
/// per level, with a fold chevron before it when it has subfolders.
private struct PhoneFolderRow: View {
    let model: AppModel
    let symbol: String
    let name: String
    let path: String
    let count: Int
    var depth: Int? = nil
    var hasChildren = false
    let isLast: Bool
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let folded = model.isFolderFolded(path)
        HStack(spacing: 0) {
            if depth != nil {
                Button { withAnimation(.snappy) { model.toggleFolderFolded(path) } } label: {
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 13, weight: .bold)
                        .rotationEffect(.degrees(folded ? 0 : 90))
                        .foregroundStyle(theme.color(\.accent))
                        .opacity(hasChildren ? 1 : 0)
                        .frame(width: 30)
                        .frame(maxHeight: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!hasChildren)
                .accessibilityHidden(!hasChildren)
                .accessibilityLabel(folded ? "Expand \(name)" : "Collapse \(name)")
            }
            Button { nav.push(.folder(path)) } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .scaledFont(size: 18)
                        .foregroundStyle(theme.color(\.link))
                        .frame(width: 24)
                    HStack(spacing: 8) {
                        Text(name)
                            .scaledFont(size: 17)
                            .foregroundStyle(theme.color(\.fg))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(count)").scaledFont(size: 17).foregroundStyle(theme.color(\.muted))
                        Image(systemName: "chevron.right")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(theme.color(\.muted))
                    }
                    .padding(.vertical, 11)
                    .padding(.trailing, 14)
                    .scaledMinHeight(44)
                    .overlay(alignment: .bottom) { if !isLast { Hairline() } }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name), \(count == 1 ? "1 note" : "\(count) notes")")
        }
        .padding(.leading, depth.map { 8 + CGFloat($0) * 28 } ?? 16)
    }
}

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
