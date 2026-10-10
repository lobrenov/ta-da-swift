// The embed menu, for an image an `![[ ]]` draws: Copy, Cut, Rename…, Reveal in Finder and Delete on the Mac (a
// right-click, in the file menu's panel); Copy, Cut, Edit Markdown, Rename…, Show in Files and Delete on iPhone (press
// and hold). Rename and Delete open the image dialogs (`ImageDialogs.swift`). LiveEditor opens it.
import SwiftUI
import UniformTypeIdentifiers
import TaDaCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension AppModel {
    /// Puts the image at `path` on the pasteboard: its file, which a paste in Ta Da embeds as it is, and its data for
    /// other apps. The data is read off the main actor; `then` runs once the pasteboard has it.
    func copyImage(_ path: String, then: @escaping () -> Void = {}) {
        guard let vault else { return }
        let url = vault.url(for: path)
        let type = UTType(filenameExtension: url.pathExtension) ?? .image
        Task {
            let data = await Self.contents(of: url)
            #if os(macOS)
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            if let data { item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier)) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([item])
            #else
            var item: [String: Any] = [UTType.fileURL.identifier: url]
            if let data { item[type.identifier] = data }
            UIPasteboard.general.setItems([item])
            #endif
            then()
        }
    }

    @concurrent nonisolated private static func contents(of url: URL) async -> Data? {
        try? Data(contentsOf: url)
    }
}

#if os(macOS)
extension FileMenuAction {
    /// The embed menu for the image at `path`. `cut` takes the `![[ ]]` out once the image is copied.
    static func embedActions(for path: String, model: AppModel, cut: @escaping () -> Void) -> [FileMenuAction] {
        [
            FileMenuAction(title: "Copy", systemImage: "doc.on.doc", shortcut: "⌘C") { model.copyImage(path) },
            FileMenuAction(title: "Cut", systemImage: "scissors", shortcut: "⌘X") { model.copyImage(path, then: cut) },
            FileMenuAction(title: "Rename…", systemImage: "pencil", shortcut: "", startsGroup: true) {
                model.imageDialog = .rename(path)
            },
            FileMenuAction(title: "Reveal in Finder", systemImage: "arrow.up.forward.square", shortcut: "") {
                model.revealInFinder([path])
            },
            FileMenuAction(title: "Delete", systemImage: "trash", shortcut: "⌘⌫") { model.imageDialog = .delete(path) },
        ]
    }
}
#else
enum EmbedMenu {
    /// The press-and-hold menu for the image at `path`. `cut` takes the `![[ ]]` out once the image is copied;
    /// `editMarkdown` shows it.
    static func menu(for path: String, model: AppModel, cut: @escaping () -> Void, editMarkdown: @escaping () -> Void) -> UIMenu {
        let edits = UIMenu(options: .displayInline, children: [
            UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in model.copyImage(path) },
            UIAction(title: "Cut", image: UIImage(systemName: "scissors")) { _ in model.copyImage(path, then: cut) },
            UIAction(title: "Edit Markdown", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right")) { _ in
                editMarkdown()
            },
            UIAction(title: "Rename…", image: UIImage(systemName: "pencil")) { _ in model.imageDialog = .rename(path) },
            UIAction(title: "Show in Files", image: UIImage(systemName: "folder")) { _ in model.showInFiles(path) },
        ])
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            model.imageDialog = .delete(path)
        }
        return UIMenu(children: [edits, UIMenu(options: .displayInline, children: [delete])])
    }
}

extension AppModel {
    /// Opens the Files app at the file at `path`.
    func showInFiles(_ path: String) {
        guard let vault, let url = URL(string: "shareddocuments://" + vault.url(for: path).path(percentEncoded: true)) else { return }
        UIApplication.shared.open(url)
    }
}
#endif
