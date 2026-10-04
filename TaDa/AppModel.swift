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
        didSet {
            guard selection != oldValue else { return }
            if selection == nil { isSourceMode = false }
            Task { await loadSelection() }
        }
    }
    /// Source mode shows the whole file, frontmatter included, full width with the file inspector.
    /// It ends when nothing is selected, so picking another domain brings the lists back.
    var isSourceMode = false
    /// The selected file's text. It stays on the previous file until the new one has been read.
    private(set) var document: OpenDocument?
    /// Why the selected file couldn't be opened.
    private(set) var documentError: String?
    /// A file whose title field should take focus when it opens (a file just created).
    var titleFocus: String?
    /// The last failed file operation, or a note about edits kept in a copy, shown as an alert.
    var errorMessage: String?
    /// Search text from the sidebar; while it isn't empty the browser shows matches.
    var searchText = ""
    /// Bumped by the Search Files command; the sidebar's search field takes focus.
    var searchFocusRequest = 0
    /// The browser list on screen, top to bottom, for the arrow keys. Set by the list itself.
    struct ArrowKeyList: Equatable {
        var id: UUID
        var paths: [String]
    }
    @ObservationIgnored var arrowKeyList: ArrowKeyList?
    /// Whether FSEvents is watching the folder. Without it, changes are picked up when the app becomes active.
    private(set) var isWatching = false
    /// Refreshed when the day changes, so every query uses the same `today`.
    var today = LocalDate(Date())

    var themeSet: ThemeSet {
        didSet { defaults.set(themeSet.name, forKey: Keys.themeSet) }
    }
    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    /// Use `lightScheme` and `darkScheme` instead of the theme set's pair. Turning it on starts from the set's pair.
    var usesSchemePerAppearance: Bool {
        didSet {
            defaults.set(usesSchemePerAppearance, forKey: Keys.usesSchemePerAppearance)
            if usesSchemePerAppearance, !oldValue {
                lightScheme = themeSet.light
                darkScheme = themeSet.dark
            }
        }
    }
    var lightScheme: Theme {
        didSet { defaults.set(lightScheme.name, forKey: Keys.lightScheme) }
    }
    var darkScheme: Theme {
        didSet { defaults.set(darkScheme.name, forKey: Keys.darkScheme) }
    }
    /// The Mac's appearance, kept current by ContentView.
    var systemIsDark = Appearance.systemIsDark

    var isDark: Bool {
        switch appearance {
        case .system: systemIsDark
        case .light: false
        case .dark: true
        }
    }
    var shownLightScheme: Theme { usesSchemePerAppearance ? lightScheme : themeSet.light }
    var shownDarkScheme: Theme { usesSchemePerAppearance ? darkScheme : themeSet.dark }
    var theme: Theme { isDark ? shownDarkScheme : shownLightScheme }

    /// Picks a bundled set and stops using separate schemes.
    func choose(_ set: ThemeSet) {
        themeSet = set
        usesSchemePerAppearance = false
    }

    private let defaults: UserDefaults
    private var pendingSave: Task<Void, Never>?
    /// The save in progress; each save waits for the one before, so writes land in order.
    private var saving: Task<Void, Never>?
    /// The folder whose security-scoped access is held while it's open.
    private var accessedFolder: URL?
    private var watcher: VaultWatcher?
    /// Modification dates of the folder's Markdown files as last seen, to find what changed.
    private var fileDates: [String: Date] = [:]
    private var refreshing: Task<Void, Never>?
    private var refreshAgain = false

    enum Keys {
        static let bookmark = "vaultBookmark"
        static let themeSet = "themeSet"
        static let appearance = "appearance"
        static let usesSchemePerAppearance = "usesSchemePerAppearance"
        static let lightScheme = "lightScheme"
        static let darkScheme = "darkScheme"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        themeSet = defaults.string(forKey: Keys.themeSet).flatMap(ThemeSet.named) ?? .standard
        appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init) ?? .system
        usesSchemePerAppearance = defaults.bool(forKey: Keys.usesSchemePerAppearance)
        lightScheme = defaults.string(forKey: Keys.lightScheme).flatMap(Theme.named) ?? ThemeSet.standard.light
        darkScheme = defaults.string(forKey: Keys.darkScheme).flatMap(Theme.named) ?? ThemeSet.standard.dark
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
        watcher = nil
        state = .loading
        // Dates first: anything that changes while the index loads shows up as changed on the next refresh.
        fileDates = await Self.modificationDates(in: vault)
        index = await vault.loadIndex()
        state = .ready
        watcher = VaultWatcher(root: vault.root) { [weak self] in
            Task { await self?.refresh() }
        }
        isWatching = watcher != nil
    }

    @concurrent nonisolated private static func modificationDates(in vault: Vault) async -> [String: Date] {
        vault.modificationDates()
    }

    // MARK: Changes made outside Ta Da

    /// Brings the index and the open document up to date with the files on disk. Runs when the folder
    /// watcher fires and when the app becomes active. Calls during a refresh fold into one more pass.
    func refresh() async {
        guard let vault else { return }
        if let refreshing {
            refreshAgain = true
            await refreshing.value
            return
        }
        let task = Task {
            repeat {
                refreshAgain = false
                let changes = await Self.changes(in: vault, since: fileDates)
                guard self.vault?.root == vault.root else { return }
                fileDates = changes.dates
                await apply(changes, from: vault)
            } while refreshAgain
        }
        refreshing = task
        await task.value
        refreshing = nil
    }

    private func apply(_ changes: VaultChanges, from vault: Vault) async {
        let open = document
        for path in changes.removed where path != open?.path { index.remove(path) }
        for (path, item) in changes.changed where path != open?.path {
            if let item { index.update(item) } else { index.remove(path) }
        }
        guard let open else { return }
        if changes.removed.contains(open.path) {
            if open.isDirty {
                open.isRemovedOnDisk = true
            } else {
                index.remove(open.path)
                if selection == open.path { selection = nil }
            }
        } else if changes.changed.keys.contains(open.path) {
            await reload(open, from: vault)
        }
    }

    /// Takes the file's new text if there are no unsaved edits; otherwise keeps them and asks.
    private func reload(_ document: OpenDocument, from vault: Vault) async {
        guard let (disk, modified) = try? await Self.read(document.path, in: vault) else { return }
        document.conflicts = await Self.conflicts(of: document.path, in: vault)
        guard disk != document.savedText else { return }
        if document.isDirty, disk != document.text {
            document.diskText = disk
        } else {
            document.savedText = disk
            document.modified = modified
            document.text = disk
        }
    }

    /// Keeps the unsaved edits and overwrites the other app's change.
    func keepMine(_ document: OpenDocument) async {
        guard let disk = document.diskText else { return }
        document.savedText = disk
        document.diskText = nil
        await save(document)
    }

    /// Drops the unsaved edits and shows the file as the other app left it.
    func useTheirs(_ document: OpenDocument) {
        guard let disk = document.diskText else { return }
        document.diskText = nil
        document.savedText = disk
        document.text = disk
    }

    /// Writes a file that was deleted outside Ta Da back, with the unsaved edits.
    func saveAgain(_ document: OpenDocument) async {
        guard let vault else { return }
        do {
            document.modified = try await Self.write(document.text, to: document.path, in: vault)
            document.savedText = document.text
            document.isRemovedOnDisk = false
            if let item = document.item { index.update(item) }
        } catch {
            errorMessage = "Ta Da couldn’t save “\(Item.title(ofPath: document.path))”. (\(error.localizedDescription))"
        }
    }

    /// Lets a file that was deleted outside Ta Da go, with its unsaved edits.
    func discardRemoved(_ document: OpenDocument) {
        document.savedText = document.text
        index.remove(document.path)
        if selection == document.path { selection = nil }
    }

    /// Keeps the file as it is and discards iCloud's other versions.
    func keepCurrentVersion(_ document: OpenDocument) async {
        guard let vault else { return }
        let url = vault.url(for: document.path)
        do {
            try await Self.run { try Conflicts.keepCurrent(url) }
            document.conflicts = []
        } catch {
            errorMessage = "Ta Da couldn’t resolve the conflict. (\(error.localizedDescription))"
        }
    }

    /// Replaces the file with one of iCloud's other versions.
    func adopt(_ version: ConflictVersion, for document: OpenDocument) async {
        guard let vault else { return }
        let url = vault.url(for: document.path)
        do {
            let text = try await Self.run { try Conflicts.adopt(version, at: url) }
            document.conflicts = []
            document.diskText = nil
            document.savedText = text
            document.text = text
        } catch {
            errorMessage = "Ta Da couldn’t use the other version. (\(error.localizedDescription))"
        }
    }

    @concurrent nonisolated private static func changes(in vault: Vault, since known: [String: Date]) async -> VaultChanges {
        vault.changes(since: known)
    }

    @concurrent nonisolated private static func conflicts(of path: String, in vault: Vault) async -> [ConflictVersion] {
        Conflicts.versions(of: vault.url(for: path))
    }

    @concurrent nonisolated private static func run<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
        try work()
    }

    // MARK: Navigation

    /// Shows a domain from the sidebar or a menu, ending any search.
    func show(_ domain: Domain) {
        searchText = ""
        self.domain = domain
    }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// ↑/↓: selects the task `offset` places away in the list on screen, or its first or last task when
    /// none is selected. False when there's no list or no task that way.
    @discardableResult
    func moveSelection(by offset: Int) -> Bool {
        guard let paths = arrowKeyList?.paths, !paths.isEmpty else { return false }
        let next = selection.flatMap { paths.firstIndex(of: $0) }.map { $0 + offset } ?? (offset > 0 ? 0 : paths.count - 1)
        guard paths.indices.contains(next) else { return false }
        selection = paths[next]
        return true
    }

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
        if let previous = document {
            await save(previous)
            await keepUnsavedEdits(of: previous)
        }
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
            document.conflicts = await Self.conflicts(of: path, in: vault)
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

    /// Writes unsaved edits, unless another app changed or removed the file since Ta Da read it:
    /// then nothing is written and the document asks what to keep.
    private func write(_ document: OpenDocument) async {
        guard let vault, document.isDirty, document.diskText == nil, !document.isRemovedOnDisk else { return }
        let text = document.text, path = document.path
        do {
            switch try await Self.write(text, to: path, ifUnchangedFrom: document.savedText, in: vault) {
            case let .written(modified):
                document.savedText = text
                document.modified = modified
                if let modified { fileDates[path] = modified }
            case let .changed(disk):
                document.diskText = disk
            case .missing:
                document.isRemovedOnDisk = true
            }
        } catch {
            errorMessage = "Ta Da couldn’t save “\(Item.title(ofPath: path))”. (\(error.localizedDescription))"
        }
    }

    /// When unsaved edits couldn't be saved (the file changed or went away outside Ta Da) and the document
    /// is being left, writes them to a new file beside it so nothing is lost.
    private func keepUnsavedEdits(of document: OpenDocument) async {
        guard let vault, document.isDirty else { return }
        let path = document.path, text = document.text
        let title = document.isRemovedOnDisk ? Item.title(ofPath: path) : "\(Item.title(ofPath: path)) (unsaved edits)"
        do {
            let copy = try await Self.create(text, in: Vault.folder(of: path), title: title, vault: vault)
            if let item = Item(parsing: text, path: copy) { index.update(item) }
            document.savedText = text
            errorMessage = "“\(Item.title(ofPath: path))” changed outside Ta Da while you were editing it, so your edits were saved as “\(Item.title(ofPath: copy))”."
        } catch {
            errorMessage = "Ta Da couldn’t keep your edits to “\(Item.title(ofPath: path))”. (\(error.localizedDescription))"
        }
    }

    /// Saves unsaved edits before the app quits. Synchronous, because there's no later chance.
    /// If another app changed the file meanwhile, the edits go to a copy instead.
    func saveBeforeQuitting() {
        guard let vault, let document, document.isDirty else { return }
        let path = document.path
        if !document.isRemovedOnDisk, document.diskText == nil {
            do {
                if try vault.write(document.text, to: path, ifUnchangedFrom: document.savedText) == nil { return }
            } catch {}
        }
        let title = document.isRemovedOnDisk ? Item.title(ofPath: path) : "\(Item.title(ofPath: path)) (unsaved edits)"
        _ = try? vault.create(document.text, in: Vault.folder(of: path), title: title)
    }

    private enum WriteResult: Sendable {
        case written(Date?)
        /// Another app changed the file; this is its text.
        case changed(String)
        case missing
    }

    @concurrent nonisolated private static func write(
        _ text: String, to path: String, ifUnchangedFrom expected: String, in vault: Vault
    ) async throws -> WriteResult {
        guard FileManager.default.fileExists(atPath: vault.url(for: path).path(percentEncoded: false)) else { return .missing }
        if let disk = try vault.write(text, to: path, ifUnchangedFrom: expected) { return .changed(disk) }
        return .written(vault.modificationDate(of: path))
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
        if let document, document.path == path {
            await save(document)
            guard !document.isDirty else {
                errorMessage = "“\(Item.title(ofPath: path))” changed outside Ta Da. Choose which version to keep before renaming it."
                return
            }
        }
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
            let path = try await Self.create(text, in: folder, title: "Untitled", vault: vault)
            if let item = Item(parsing: text, path: path) { index.update(item) }
            titleFocus = path
            return path
        } catch {
            errorMessage = "Ta Da couldn’t create a file in “\(folder)”. (\(error.localizedDescription))"
            return nil
        }
    }

    @concurrent nonisolated private static func create(_ text: String, in folder: String, title: String, vault: Vault) async throws -> String {
        try vault.create(text, in: folder, title: title)
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
