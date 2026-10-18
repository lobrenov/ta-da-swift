// Settings ▸ Vault: the folder's location, sync and contents, and the folders new files go in.
#if os(macOS)
import AppKit
import SwiftUI
import TaDaCore

struct VaultSettingsView: View {
    @Bindable var model: AppModel
    @State private var isPicking = false
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Vault", summary: "Ta Da reads and writes plain markdown files in this folder.") {
            VStack(spacing: 0) {
                row("Location") {
                    Image(systemName: "folder")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.color(\.accent))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.vault == nil ? "No folder" : model.folderDisplayName.replacing("/", with: " › "))
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.color(\.strong))
                        if let root = model.vault?.root {
                            Text(root.path(percentEncoded: false))
                                .font(.system(size: 11).monospaced())
                                .foregroundStyle(theme.color(\.muted))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsButton(model.vault == nil ? "Choose…" : "Change…") { isPicking = true }
                    SettingsButton("Reveal in Finder") {
                        if let root = model.vault?.root { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                    }
                    .disabled(model.vault == nil)
                }
                if model.vault != nil {
                    Hairline()
                    row("Sync") {
                        Circle()
                            .fill(theme.color(model.isInICloud ? \.done : \.blocked))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(syncDescription)
                    }
                    Hairline()
                    row("Contents") {
                        Text("^[\(model.index.tasks.count) task](inflect: true) · ^[\(model.index.projects.count) project](inflect: true) · ^[\(model.index.areas.count) area](inflect: true)")
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Folders in the vault")
                VStack(spacing: 0) {
                    folder(Vault.taskFolder + "/", "New tasks, one markdown file each")
                    folder(Vault.projectFolder + "/", "New projects, one markdown file each")
                    folder(Vault.areaFolder + "/", "New areas, one markdown file each")
                    if model.dailyFolder == model.weekFolder || !model.weekNotes {
                        folder(noteFolder(model.dailyFolder), model.weekNotes && model.dailyFolder == model.weekFolder
                               ? "Daily and week notes" : "Daily notes")
                    } else {
                        folder(noteFolder(model.dailyFolder), "Daily notes")
                        folder(noteFolder(model.weekFolder), "Week notes")
                    }
                }
                .padding(.vertical, 6)
                .background(theme.color(\.code), in: .rect(cornerRadius: 10))
            }
        }
        .folderImporter(isPresented: $isPicking, model: model)
    }

    private var syncDescription: String {
        let place = model.isInICloud ? "iCloud Drive" : "Local only, not synced to your other devices"
        let watching = model.isWatching ? "watching for changes" : "checks for changes when you switch back"
        return "\(place) · \(watching)"
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .foregroundStyle(theme.color(\.muted))
                .frame(width: 84, alignment: .leading)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A note folder as the list shows it, with the vault's top level as `/`.
    private func noteFolder(_ path: String) -> String { path.isEmpty ? "/" : path + "/" }

    private func folder(_ path: String, _ description: String) -> some View {
        HStack(spacing: 16) {
            Text(path)
                .font(.system(size: 12).monospaced())
                .foregroundStyle(theme.color(\.accent))
                .frame(width: 120, alignment: .leading)
            Text(description)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
