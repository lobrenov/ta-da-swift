// One note in a browser list: taskRow's layout with a page icon in place of the checkbox, its title, and a meta line of
// subtasks and tags, with the folder last where the list mixes folders.
import SwiftUI
import TaDaCore

struct NoteRow: View {
    let item: Item
    let selected: Bool
    /// Tag pages and search results show the folder; a folder's page doesn't.
    var showsFolder = false
    let onSelect: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let subtasks = item.subtasks
        let folder = Vault.folder(of: item.path)
        let hasMeta = subtasks.total > 0 || !item.tags.isEmpty || showsFolder
        HStack(alignment: .top, spacing: 10) {
            NoteIcon().padding(.top, 2)
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13.5))
                        .foregroundStyle(theme.color(selected ? \.strong : \.fg))
                        .lineLimit(2)
                    if hasMeta {
                        HStack(spacing: 12) {
                            if subtasks.total > 0 {
                                Chip(systemImage: "checklist", text: "\(subtasks.done)/\(subtasks.total)",
                                     spoken: "\(subtasks.done) of \(subtasks.total) subtasks done")
                            }
                            TagCountChip(tags: item.tags)
                            if showsFolder {
                                Chip(systemImage: folder.isEmpty ? "tray" : "folder", tint: \.link,
                                     text: folder.isEmpty ? "Loose" : folder, spoken: "In \(folder.isEmpty ? "Loose" : folder)")
                            }
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.color(\.muted))
                        .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Note \(item.title)")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
    }
}
