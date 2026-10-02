// The app's root state: the chosen folder, its index, the sidebar selection and the theme.
import Foundation
import TaDaCore

@Observable final class AppModel {
    enum Domain: Hashable {
        case today, upcoming, loose
        /// A project, by vault-relative path.
        case project(String)
    }

    enum VaultState: Equatable {
        /// First run, or the user hasn't picked a folder yet.
        case noFolder
        case loading
        case ready
        /// The saved folder couldn't be opened (moved, deleted, or access lost).
        case failed(String)
    }

    private(set) var state = VaultState.noFolder
    private(set) var vault: Vault?
    private(set) var index = VaultIndex()
    var domain = Domain.today {
        didSet { if domain != oldValue { selection = nil } }
    }
    /// The file shown in the document pane, by vault-relative path. Picking another domain clears it.
    var selection: String?
    /// The last failed file operation, shown as an alert.
    var errorMessage: String?
    /// Refreshed when the day changes, so every query uses the same `today`.
    var today = LocalDate(Date())

    var themeName: String {
        didSet { defaults.set(themeName, forKey: Keys.theme) }
    }
    var theme: Theme { Theme.named(themeName) }

    private let defaults: UserDefaults
    /// The folder whose security-scoped access is held while it's open.
    private var accessedFolder: URL?

    private enum Keys {
        static let bookmark = "vaultBookmark"
        static let theme = "themeName"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        themeName = defaults.string(forKey: Keys.theme) ?? Theme.all[0].name
    }

    // MARK: Folder

    /// Opens the saved folder, if there is one.
    func start() async {
        guard let bookmark = defaults.data(forKey: Keys.bookmark) else {
            state = .noFolder
            return
        }
        do {
            let resolved = try Vault.resolve(bookmark)
            if let refreshed = resolved.refreshed { defaults.set(refreshed, forKey: Keys.bookmark) }
            await open(resolved.folder)
        } catch {
            state = .failed("Ta Da couldn’t open the saved folder. It may have been moved or deleted. (\(error.localizedDescription))")
        }
    }

    /// Saves a folder the user picked and opens it. `folder` is the security-scoped URL from the picker.
    func choose(_ folder: URL) async {
        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }
        do {
            defaults.set(try Vault.bookmark(for: folder), forKey: Keys.bookmark)
        } catch {
            state = .failed("Ta Da couldn’t keep access to “\(folder.lastPathComponent)”. (\(error.localizedDescription))")
            return
        }
        domain = .today
        await start()
    }

    private func open(_ folder: URL) async {
        accessedFolder?.stopAccessingSecurityScopedResource()
        accessedFolder = folder.startAccessingSecurityScopedResource() ? folder : nil
        let vault = Vault(root: folder)
        self.vault = vault
        state = .loading
        index = await vault.loadIndex()
        state = .ready
    }

    // MARK: Navigation

    /// Shows a file: a project opens as its own page in its domain; a task opens beside the current list.
    func open(_ path: String) {
        guard let item = index[path] else { return }
        if item.properties.kind == .project { domain = .project(path) }
        selection = path
    }

    // MARK: Editing files

    /// Completes an open task or reopens a done one. Only `status` and `completedDate` change.
    func toggleCompletion(_ item: Item) async {
        let today = today, fallback = item.properties.status
        await edit(item.path) { text in
            Completion.toggle(Item(parsing: text, path: item.path)?.properties.status ?? fallback, in: text, today: today)
        }
    }

    /// Applies a text change to one file in a single coordinated read and write, then patches the index.
    func edit(_ path: String, _ transform: @escaping @Sendable (String) -> String) async {
        guard let vault else { return }
        do {
            let item = try await Self.update(path, in: vault, transform)
            if let item { index.update(item) } else { index.remove(path) }
        } catch {
            errorMessage = "Ta Da couldn’t save “\(Item.title(ofPath: path))”. (\(error.localizedDescription))"
        }
    }

    @concurrent nonisolated private static func update(
        _ path: String, in vault: Vault, _ transform: @Sendable (String) -> String
    ) async throws -> Item? {
        try vault.update(path, transform)
    }

    // MARK: Queries for the sidebar

    var todayCount: Int { index.today(today).count { $0.properties.status != .done } }
    var looseCount: Int { index.loose().count }
    var projects: [ProjectProgress] { index.activeProjects() }

    var folderDisplayName: String { vault.map { Self.displayName(for: $0.root) } ?? "" }
    var isInICloud: Bool { vault?.root.pathComponents.contains("Mobile Documents") ?? false }

    /// "iCloud Drive/Ta Da" or "Obsidian/Personal" for folders in iCloud Drive, otherwise the folder's name.
    static func displayName(for root: URL) -> String {
        let components = root.pathComponents
        if let mobile = components.firstIndex(of: "Mobile Documents"), mobile + 1 < components.count {
            let container = components[mobile + 1]
            let rest = components.dropFirst(mobile + 2)
            if container == "com~apple~CloudDocs" { return (["iCloud Drive"] + rest).joined(separator: "/") }
            if container.hasSuffix("~obsidian"), rest.first == "Documents" { return (["Obsidian"] + rest.dropFirst()).joined(separator: "/") }
        }
        return root.lastPathComponent
    }
}
