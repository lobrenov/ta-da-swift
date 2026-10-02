// The app's root state: the chosen folder, its index, the sidebar selection, the open document and the theme.
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
    var selection: String? {
        didSet { if selection != oldValue { Task { await loadSelection() } } }
    }
    /// The selected file's text. It stays on the previous file until the new one has been read.
    private(set) var document: OpenDocument?
    /// Why the selected file couldn't be opened.
    private(set) var documentError: String?
    /// A file whose title field should take focus when it opens (a file just created).
    var titleFocus: String?
    /// The last failed file operation, shown as an alert.
    var errorMessage: String?
    /// Refreshed when the day changes, so every query uses the same `today`.
    var today = LocalDate(Date())

    var themeName: String {
        didSet { defaults.set(themeName, forKey: Keys.theme) }
    }
    var theme: Theme { Theme.named(themeName) }

    private let defaults: UserDefaults
    private var pendingSave: Task<Void, Never>?
    /// The save in progress; each save waits for the one before, so writes land in order.
    private var saving: Task<Void, Never>?
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

    /// Opens the saved folder, if there is one and it isn't open already (a reopened window calls this again).
    func start() async {
        guard vault == nil else { return }
        await openSavedFolder()
    }

    private func openSavedFolder() async {
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
        await openSavedFolder()
    }

    private func open(_ folder: URL) async {
        accessedFolder?.stopAccessingSecurityScopedResource()
        accessedFolder = folder.startAccessingSecurityScopedResource() ? folder : nil
        let vault = Vault(root: folder)
        self.vault = vault
        selection = nil
        document = nil
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

    // MARK: The open document

    /// Reads the selected file into `document`, saving the previous one first.
    func loadSelection() async {
        guard let vault, document?.path != selection else { return }
        if let previous = document { await save(previous) }
        guard let path = selection else {
            document = nil
            return
        }
        do {
            let (text, modified) = try await Self.read(path, in: vault)
            guard selection == path, document?.path != path else { return }
            let document = OpenDocument(path: path, text: text, modified: modified)
            document.onChange = { [weak self, weak document] in
                if let self, let document { self.documentChanged(document) }
            }
            self.document = document
            documentError = nil
        } catch {
            guard selection == path else { return }
            document = nil
            documentError = "Ta Da couldn’t open “\(Item.title(ofPath: path))”. (\(error.localizedDescription))"
        }
    }

    private func documentChanged(_ document: OpenDocument) {
        if let item = document.item {
            if index[item.path] != item { index.update(item) }
        } else {
            index.remove(document.path)
        }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.save(document)
        }
    }

    /// Writes the document if it has unsaved changes. Saves run one after another.
    func save(_ document: OpenDocument) async {
        let previous = saving
        let task = Task {
            await previous?.value
            await write(document)
        }
        saving = task
        await task.value
    }

    private func write(_ document: OpenDocument) async {
        guard let vault, document.isDirty else { return }
        let text = document.text, path = document.path
        do {
            document.modified = try await Self.write(text, to: path, in: vault)
            document.savedText = text
        } catch {
            errorMessage = "Ta Da couldn’t save “\(Item.title(ofPath: path))”. (\(error.localizedDescription))"
        }
    }

    /// Saves unsaved edits before the app quits. Synchronous, because there's no later chance.
    func saveBeforeQuitting() {
        guard let vault, let document, document.isDirty else { return }
        try? vault.write(document.text, to: document.path)
    }

    @concurrent nonisolated private static func read(_ path: String, in vault: Vault) async throws -> (String, Date?) {
        (try vault.read(path), vault.modificationDate(of: path))
    }

    @concurrent nonisolated private static func write(_ text: String, to path: String, in vault: Vault) async throws -> Date? {
        try vault.write(text, to: path)
        return vault.modificationDate(of: path)
    }

    // MARK: Editing files

    /// Completes an open task or reopens a done one. Only `status` and `completedDate` change.
    func toggleCompletion(_ item: Item) async {
        let today = today, fallback = item.properties.status
        await edit(item.path) { text in
            Completion.toggle(Item(parsing: text, path: item.path)?.properties.status ?? fallback, in: text, today: today)
        }
    }

    /// Applies a text change to one file, then patches the index. The open document is changed in memory
    /// and saved after a pause; any other file in a single coordinated read and write.
    func edit(_ path: String, _ transform: @escaping @Sendable (String) -> String) async {
        if let document, document.path == path {
            document.text = transform(document.text)
            return
        }
        guard let vault else { return }
        do {
            let item = try await Self.update(path, in: vault, transform)
            if let item { index.update(item) } else { index.remove(path) }
        } catch {
            errorMessage = "Ta Da couldn’t save “\(Item.title(ofPath: path))”. (\(error.localizedDescription))"
        }
    }

    /// Sets one frontmatter property, or empties it when `value` is nil.
    func setProperty(_ key: String, to value: PropertyValue?, in path: String) async {
        await edit(path) { text in
            value.map { FrontmatterEditor.set(key, to: $0, in: text) } ?? FrontmatterEditor.clear(key, in: text)
        }
    }

    /// Sets the status; Done also sets `completedDate`, anything else clears it.
    func setStatus(_ status: Status, in path: String) async {
        let today = today
        await edit(path) { Completion.setStatus(status, in: $0, today: today) }
    }

    /// Renames a file from a new title. Renaming a project also rewrites the `project:` link in its tasks.
    func rename(_ path: String, to title: String) async {
        guard let vault, Item.title(ofPath: path) != title else { return }
        if let document, document.path == path { await save(document) }
        do {
            let (newPath, items) = try await Self.rename(path, to: title, in: vault, index: index)
            guard newPath != path else { return }
            index.remove(path)
            for item in items { index.update(item) }
            if let document, document.path == path { document.path = newPath }
            if domain == .project(path) { domain = .project(newPath) }
            if selection == path || selection == nil && domain == .project(newPath) { selection = newPath }
        } catch {
            errorMessage = "Ta Da couldn’t rename “\(Item.title(ofPath: path))”. (\(error.localizedDescription))"
        }
    }

    @concurrent nonisolated private static func rename(
        _ path: String, to title: String, in vault: Vault, index: VaultIndex
    ) async throws -> (String, [Item]) {
        let result = index[path]?.properties.kind == .project
            ? try vault.renameProject(at: path, to: title, index: index)
            : (path: try vault.rename(path, to: title), relinked: [])
        return (result.path, try ([result.path] + result.relinked).compactMap { try vault.load($0) })
    }

    // MARK: New files

    /// Creates an untitled task and selects it with its title ready to type. In a project it's linked to the
    /// project; in Today it's due today; anywhere else it opens in Loose tasks.
    func newTask() async {
        var project: Item?
        if case let .project(path) = domain { project = index[path] }
        var text = NewFile.task(project: project?.title, today: today)
        if project == nil, domain == .today { text = FrontmatterEditor.set("dueDate", to: .date(today), in: text) }
        guard let path = await create(text, in: Vault.taskFolder) else { return }
        if project == nil, domain != .today { domain = .loose }
        selection = path
    }

    /// Creates an untitled project and opens its page with its title ready to type.
    func newProject() async {
        guard let path = await create(NewFile.project(today: today), in: Vault.projectFolder) else { return }
        open(path)
    }

    private func create(_ text: String, in folder: String) async -> String? {
        guard let vault else { return nil }
        do {
            let path = try await Self.create(text, in: folder, vault: vault)
            if let item = Item(parsing: text, path: path) { index.update(item) }
            titleFocus = path
            return path
        } catch {
            errorMessage = "Ta Da couldn’t create a file in “\(folder)”. (\(error.localizedDescription))"
            return nil
        }
    }

    @concurrent nonisolated private static func create(_ text: String, in folder: String, vault: Vault) async throws -> String {
        try vault.create(text, in: folder, title: "Untitled")
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
