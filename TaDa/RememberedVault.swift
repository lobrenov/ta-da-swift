// A folder opened on this device, as the vault switcher lists it.
import Foundation
import TaDaCore

struct RememberedVault: Identifiable, Equatable {
    let bookmark: Data
    /// The folder's name.
    let name: String
    /// Where the folder is: "On My iPhone", or its parent as `AppModel.displayName(for:)` names it ("iCloud Drive",
    /// "Obsidian/Personal", or the parent folder's name).
    let location: String
    /// The folder is in iCloud Drive.
    let isInICloud: Bool
    /// The bookmark no longer resolves: the folder was deleted or is out of reach.
    let isMissing: Bool
    let isOpen: Bool
    /// The folder's path, resolving symlinks; the path the bookmark recorded when it's missing.
    let path: String

    var id: Data { bookmark }

    init(bookmark: Data, openPath: String?) {
        self.bookmark = bookmark
        let resolved = try? Vault.resolve(bookmark)
        isMissing = resolved == nil
        let folder = resolved?.folder
            ?? URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark)?.path.map { URL(filePath: $0) }
            ?? URL(filePath: "/")
        path = folder.resolvingSymlinksInPath().path
        name = folder.lastPathComponent
        location = path.contains("/File Provider Storage/") ? "On My iPhone" : AppModel.displayName(for: folder.deletingLastPathComponent())
        isInICloud = path.contains("/Mobile Documents/")
        isOpen = path == openPath
    }
}
