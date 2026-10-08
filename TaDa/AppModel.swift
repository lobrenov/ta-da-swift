// The app's root state: the chosen folder, its index, the sidebar selection, the open document and the theme.
import Foundation
import TaDaCore

@Observable final class AppModel {
    enum Domain: Hashable {
        case today, upcoming, loose, trash
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
        didSet {
            guard domain != oldValue else { return }
            selection = nil
            multiSelection = []
            trashSelection = []
            trashNote = nil
        }
    }
    /// The file shown in the document pane, by vault-relative path. Picking another domain clears it.
    var selection: String? {
        didSet {
            guard selection != oldValue else { return }
            if let selection {
                multiSelection = []
                selectionAnchor = selection
            } else {
                isSourceMode = false
            }
            let previous = loading
            previous?.cancel()
            loading = Task {
                await previous?.value
                guard !Task.isCancelled else { return }
                await loadSelection()
            }
        }
    }
    /// The load the last selection change started. Each cancels the one before, which then doesn't start, and
    /// waits for it, so loads never overlap.
    @ObservationIgnored private(set) var loading: Task<Void, Never>?
    /// Two or more tasks picked with shift- or ⌘-click in a project's list. While it's set, `selection` is nil.
    private(set) var multiSelection: Set<String> = []
    /// Where a shift-click range starts: the last task clicked on its own or ⌘-clicked.
    @ObservationIgnored private var selectionAnchor: String?
    /// Source mode shows the whole file, frontmatter included, full width with the file inspector.
    /// It ends when nothing is selected, so picking another domain brings the lists back.
    var isSourceMode = false
    /// The selected file's text. It stays on the previous file until the new one has been read.
    private(set) var document: OpenDocument? {
        didSet { if document !== oldValue { present(document) } }
    }
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
    /// The browser list on screen, top to bottom, for the arrow keys and selection clicks. Set by the list itself.
    struct ArrowKeyList: Equatable {
        var id: UUID
        var paths: [String]
        /// Shift- and ⌘-click pick several tasks.
        var allowsMultipleSelection = false
    }
    @ObservationIgnored var arrowKeyList: ArrowKeyList?
    /// The Ta Da files in `.trash/`, most recently deleted first.
    private(set) var trash: [TrashedItem] = []
    /// The files picked in the Trash list, by path.
    var trashSelection: Set<String> = []
    /// What the last restore did, shown in Trash.
    var trashNote: String?
    /// The file whose file menu is open; its row is ringed.
    var menuTarget: String?
    /// ⇧⌘M's request for the project menu, or ⌘S's and ⌘D's for a date's calendar. The view it names opens the
    /// menu and sets this back to nil.
    var propertyMenuRequest: PropertyMenuRequest?
    struct PropertyMenuRequest: Equatable {
        let id = UUID()
        let menu: Menu
        /// The files to set.
        let paths: [String]
        /// The file whose chip (`onChip`) or list row the menu opens under.
        let anchor: String
        let onChip: Bool

        enum Menu: Equatable {
            case project
            case date(AgendaEntry.Kind)
        }
    }
    /// Whether `VaultWatcher` is watching the folder. Without it, changes are picked up when the app becomes active.
    private(set) var isWatching = false
    /// Whether the folder is in iCloud Drive, or in an app's iCloud folder such as Obsidian's.
    private(set) var isInICloud = false
    /// Refreshed when the day changes, so every query uses the same `today`.
    var today = LocalDate(Date()) {
        didSet { if today != oldValue { updateLists() } }
    }

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
    var autocomplete: Autocomplete {
        didSet { defaults.set(autocomplete.dictionary, forKey: Keys.autocomplete) }
    }
    /// The task groups folded in each project's browser ("Open", "Completed"), by project path.
    private(set) var foldedGroups: [String: [String]] {
        didSet { defaults.set(foldedGroups, forKey: Keys.foldedGroups) }
    }
    /// The system appearance, kept current by `themed(by:)`.
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

    func isFolded(_ group: String, in project: String) -> Bool {
        foldedGroups[project]?.contains(group) == true
    }

    func toggleFolded(_ group: String, in project: String) {
        var groups = foldedGroups[project] ?? []
        if let i = groups.firstIndex(of: group) { groups.remove(at: i) } else { groups.append(group) }
        foldedGroups[project] = groups.isEmpty ? nil : groups
    }

    /// How long an edit waits before it's saved.
    @ObservationIgnored var saveDelay = Duration.milliseconds(600)
    private let defaults: any SettingsStore
    private var pendingSave: Task<Void, Never>?
    /// The save in progress; each save waits for the one before, so writes land in order.
    private var saving: Task<Void, Never>?
    /// The folder whose security-scoped access is held while it's open.
    private var accessedFolder: URL?
    private var watcher: VaultWatcher?
    /// The open document's file, presented to file coordination.
    @ObservationIgnored private var presenter: FilePresenter?
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
        static let foldedGroups = "foldedGroups"
        static let autocomplete = "autocomplete"
    }

    init(defaults: any SettingsStore = UserDefaults.standard) {
        self.defaults = defaults
        themeSet = defaults.string(forKey: Keys.themeSet).flatMap(ThemeSet.named) ?? .standard
        appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init) ?? .system
        usesSchemePerAppearance = defaults.bool(forKey: Keys.usesSchemePerAppearance)
        lightScheme = defaults.string(forKey: Keys.lightScheme).flatMap(Theme.named) ?? ThemeSet.standard.light
        darkScheme = defaults.string(forKey: Keys.darkScheme).flatMap(Theme.named) ?? ThemeSet.standard.dark
        foldedGroups = defaults.dictionary(forKey: Keys.foldedGroups) as? [String: [String]] ?? [:]
        autocomplete = Autocomplete(defaults.dictionary(forKey: Keys.autocomplete))
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
            state = .failed(Self.couldNot("open the saved folder. It may have been moved or deleted", error))
        }
    }

    /// Saves a folder the user picked and opens it. `folder` is the security-scoped URL from the picker.
    func choose(_ folder: URL) async {
        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }
        do {
            defaults.set(try Vault.bookmark(for: folder), forKey: Keys.bookmark)
        } catch {
            state = .failed(Self.couldNot("keep access to “\(folder.lastPathComponent)”", error))
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
        fileDates = await Self.run { vault.modificationDates() }
        let loaded = await vault.loadIndex()
        updateIndex { $0 = loaded }
        trash = await Self.run { vault.trashedItems() }
        isInICloud = await Self.run { FileManager.default.isUbiquitousItem(at: vault.root) }
        state = .ready
        #if os(iOS)
        await Self.run { vault.downloadPlaceholders() }
        #endif
        watcher = VaultWatcher(root: vault.root) { [weak self] in
            Task { await self?.refresh() }
        }
        isWatching = watcher != nil
    }

    // MARK: Changes made outside Ta Da

    /// Brings the index and the open document up to date with the files on disk. Runs when the folder
    /// watcher fires and when the app becomes active. Calls during a refresh fold into one more pass, so
    /// each call returns after a pass that started after it.
    func refresh() async {
        guard let vault else { return }
        if let refreshing {
            refreshAgain = true
            await refreshing.value
            return
        }
        let task = Task {
            // Cleared straight after the last check of `refreshAgain`, so any later call starts a new refresh.
            defer { refreshing = nil }
            repeat {
                refreshAgain = false
                #if os(iOS)
                await Self.run { vault.downloadPlaceholders() }
                #endif
                let known = fileDates, presenter = presenter
                let changes = await Self.run { vault.changes(since: known, presenter: presenter) }
                guard self.vault?.root == vault.root else { return }
                fileDates = changes.dates
                await apply(changes, from: vault)
                trash = await Self.run { vault.trashedItems() }
                trashSelection.formIntersection(trash.map(\.id))
                multiSelection = multiSelection.filter { index[$0] != nil }
            } while refreshAgain
        }
        refreshing = task
        await task.value
    }

    private func apply(_ changes: VaultChanges, from vault: Vault) async {
        guard !changes.isEmpty else { return }
        let open = document
        updateIndex { index in
            for path in changes.removed where path != open?.path { index.remove(path) }
            for (path, item) in changes.changed where path != open?.path {
                if let item { index.update(item) } else { index.remove(path) }
            }
        }
        guard let open else { return }
        if changes.removed.contains(open.path) {
            if open.isDirty {
                open.isRemovedOnDisk = true
            } else {
                updateIndex { $0.remove(open.path) }
                if selection == open.path { selection = nil }
            }
        } else if changes.changed.keys.contains(open.path) {
            await reload(open, from: vault)
        }
    }

    /// Takes the file's new text if there are no unsaved edits; otherwise keeps them and asks.
    private func reload(_ document: OpenDocument, from vault: Vault) async {
        let path = document.path, presenter = presenter
        let loaded = try? await Self.run { (try vault.read(path, presenter: presenter), vault.modificationDate(of: path)) }
        guard let (disk, modified) = loaded else { return }
        document.conflicts = await Self.run { Conflicts.versions(of: vault.url(for: path)) }
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
            let text = document.text, path = document.path
            document.modified = try await Self.run {
                try vault.write(text, to: path)
                return vault.modificationDate(of: path)
            }
            document.savedText = document.text
            document.isRemovedOnDisk = false
            if let item = document.item { updateIndex { $0.update(item) } }
            present(document)
        } catch {
            errorMessage = Self.couldNot("save “\(Item.title(ofPath: document.path))”", error)
        }
    }

    /// Lets a file that was deleted outside Ta Da go, with its unsaved edits.
    func discardRemoved(_ document: OpenDocument) {
        document.savedText = document.text
        updateIndex { $0.remove(document.path) }
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
            errorMessage = Self.couldNot("resolve the conflict", error)
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
            errorMessage = Self.couldNot("use the other version", error)
        }
    }

    /// Does file work off the main actor.
    @concurrent nonisolated private static func run<T: Sendable>(_ work: @Sendable () throws -> T) async rethrows -> T {
        try work()
    }

    /// "Ta Da couldn’t <action>. (<the error>)"
    private static func couldNot(_ action: String, _ error: any Error) -> String {
        "Ta Da couldn’t \(action). (\(error.localizedDescription))"
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
        let current = selection ?? (picked.isEmpty ? nil : selectionAnchor)
        let next = current.flatMap { paths.firstIndex(of: $0) }.map { $0 + offset } ?? (offset > 0 ? 0 : paths.count - 1)
        guard paths.indices.contains(next) else { return false }
        selectOnly(paths[next])
        return true
    }

    /// Shift-click: picks every task in the list on screen from the anchor to `path`.
    func extendSelection(to path: String) {
        guard let paths = arrowKeyList?.paths, let end = paths.firstIndex(of: path),
              let start = (selectionAnchor ?? selection).flatMap({ paths.firstIndex(of: $0) }) else {
            selectOnly(path)
            return
        }
        pick(Set(paths[min(start, end)...max(start, end)]))
    }

    /// ⌘-click: adds `path` to the picked tasks, or takes it out.
    func toggleSelection(_ path: String) {
        var picked = picked
        if picked.remove(path) == nil { picked.insert(path) }
        pick(picked)
        selectionAnchor = path
    }

    /// A plain click: opens the file, or in Trash picks just this one.
    func selectOnly(_ path: String) {
        if domain == .trash {
            trashSelection = [path]
            selectionAnchor = path
        } else {
            selection = path
        }
    }

    func clearMultiSelection() {
        multiSelection = []
    }

    /// Drops picked tasks that the list on screen no longer shows (a filter hid them, or they moved away).
    func keepPicked(in paths: [String]) {
        multiSelection.formIntersection(paths)
    }

    /// Whether a row shows as selected: the open file, or one of the picked tasks or trashed files.
    func isSelected(_ path: String) -> Bool {
        selection == path || multiSelection.contains(path) || trashSelection.contains(path)
    }

    /// The rows a click starts from: the picked trashed files in Trash, else the picked tasks or the open one.
    /// The menu bar's Reveal in Finder shows them.
    var picked: Set<String> {
        if domain == .trash { return trashSelection }
        return multiSelection.isEmpty ? Set([selection].compactMap { $0 }) : multiSelection
    }

    /// In Trash, the picked files. Elsewhere one task opens in the document pane; several show as picked
    /// with the pane empty.
    private func pick(_ paths: Set<String>) {
        if domain == .trash {
            trashSelection = paths
        } else if paths.count == 1, let path = paths.first {
            selection = path
        } else {
            selection = nil
            multiSelection = paths
        }
    }

    /// Shows a file: a project opens as its own page in its domain; a task opens beside the current list.
    func open(_ path: String) {
        guard let item = index[path] else { return }
        if item.properties.kind == .project { domain = .project(path) }
        selection = path
    }

    // MARK: The open document

    /// Reads the selected file into `document`, saving the previous one first.
    private func loadSelection() async {
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
            let presenter = presenter
            let (text, modified) = try await Self.run { (try vault.read(path, presenter: presenter), vault.modificationDate(of: path)) }
            guard selection == path, document?.path != path else { return }
            let document = OpenDocument(path: path, text: text, modified: modified)
            document.onChange = { [weak self, weak document] in
                if let self, let document { self.documentChanged(document) }
            }
            self.document = document
            documentError = nil
            document.conflicts = await Self.run { Conflicts.versions(of: vault.url(for: path)) }
        } catch {
            guard selection == path else { return }
            document = nil
            documentError = Self.couldNot("open “\(Item.title(ofPath: path))”", error)
        }
    }

    private func documentChanged(_ document: OpenDocument) {
        if let item = document.item {
            if index[item.path] != item { updateIndex(replacing: item) }
        } else if index[document.path] != nil {
            updateIndex { $0.remove(document.path) }
        }
        pendingSave?.cancel()
        pendingSave = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            await self?.save(document)
        }
    }

    /// Presents the open document's file (see `FilePresenter`): another app's coordinated read saves the
    /// edits first, and a coordinated move or rename is followed.
    private func present(_ document: OpenDocument?) {
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        presenter = nil
        guard let document, let vault else { return }
        let presenter = FilePresenter(
            url: vault.url(for: document.path),
            save: { @MainActor [weak self, weak document] in
                if let self, let document { await self.save(document) }
            },
            moved: { @MainActor [weak self, weak document] in
                if let self, let document { self.documentMoved(document) }
            }
        )
        NSFileCoordinator.addFilePresenter(presenter)
        self.presenter = presenter
    }

    /// Follows the open file to where another app moved or renamed it, if that's still a Markdown file in
    /// the folder; anywhere else `refresh()` finds it gone. Ta Da's own renames arrive here too, and following
    /// one twice changes nothing.
    private func documentMoved(_ document: OpenDocument) {
        guard let vault, document === self.document, let url = presenter?.presentedItemURL,
              let newPath = vault.path(of: url), newPath != document.path else { return }
        follow(document.path, to: newPath, items: [Item(parsing: document.text, path: newPath)].compactMap { $0 })
        document.isRemovedOnDisk = false
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
        let text = document.text, path = document.path, expected = document.savedText, presenter = presenter
        do {
            let result = try await Self.run { () throws -> WriteResult in
                guard FileManager.default.fileExists(atPath: vault.url(for: path).path(percentEncoded: false)) else { return .missing }
                if let disk = try vault.write(text, to: path, ifUnchangedFrom: expected, presenter: presenter) { return .changed(disk) }
                return .written(vault.modificationDate(of: path))
            }
            switch result {
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
            errorMessage = Self.couldNot("save “\(Item.title(ofPath: path))”", error)
        }
    }

    /// When unsaved edits couldn't be saved (the file changed or went away outside Ta Da) and the document
    /// is being left, writes them to a new file beside it so nothing is lost.
    private func keepUnsavedEdits(of document: OpenDocument) async {
        guard let vault, document.isDirty else { return }
        let path = document.path, text = document.text
        let title = document.isRemovedOnDisk ? Item.title(ofPath: path) : "\(Item.title(ofPath: path)) (unsaved edits)"
        do {
            let copy = try await Self.run { try vault.create(text, in: Vault.folder(of: path), title: title) }
            if let item = Item(parsing: text, path: copy) { updateIndex { $0.update(item) } }
            document.savedText = text
            errorMessage = "“\(Item.title(ofPath: path))” changed outside Ta Da while you were editing it, so your edits were saved as “\(Item.title(ofPath: copy))”."
        } catch {
            errorMessage = Self.couldNot("keep your edits to “\(Item.title(ofPath: path))”", error)
        }
    }

    /// Saves the open document before the app quits, after any save already under way.
    /// If another app changed or removed the file meanwhile, the edits go to a copy instead.
    func saveBeforeQuitting() async {
        guard let document else { return }
        await save(document)
        await keepUnsavedEdits(of: document)
    }

    private enum WriteResult: Sendable {
        case written(Date?)
        /// Another app changed the file; this is its text.
        case changed(String)
        case missing
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
            let item = try await Self.run { try vault.update(path, transform) }
            updateIndex { if let item { $0.update(item) } else { $0.remove(path) } }
        } catch {
            errorMessage = Self.couldNot("save “\(Item.title(ofPath: path))”", error)
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
            let index = index, presenter = presenter
            // The new path, the renamed file and its relinked tasks as they now are, and the tasks that couldn't be relinked.
            let (newPath, items, failed) = try await Self.run { () throws -> (String, [Item], [String]) in
                let result = index[path]?.properties.kind == .project
                    ? try vault.renameProject(at: path, to: title, index: index)
                    : (path: try vault.rename(path, to: title), tasks: [], failed: [])
                return (result.path, try [vault.load(result.path, presenter: presenter)].compactMap { $0 } + result.tasks, result.failed)
            }
            guard newPath != path else { return }
            follow(path, to: newPath, items: items)
            if !failed.isEmpty {
                let names = failed.map { "“\(Item.title(ofPath: $0))”" }.formatted()
                errorMessage = "Ta Da renamed “\(Item.title(ofPath: path))” to “\(Item.title(ofPath: newPath))”, but the project link in \(names) still points to the old name."
            }
        } catch {
            errorMessage = Self.couldNot("rename “\(Item.title(ofPath: path))”", error)
        }
    }

    /// Points the index, the open document and the selection at a renamed file. `items` are the files as they now are.
    private func follow(_ path: String, to newPath: String, items: [Item]) {
        updateIndex { index in
            index.remove(path)
            for item in items { index.update(item) }
        }
        if let document, document.path == path { document.path = newPath }
        if domain == .project(path) { domain = .project(newPath) }
        if selection == path || selection == nil && domain == .project(newPath) { selection = newPath }
        if let folded = foldedGroups.removeValue(forKey: path) { foldedGroups[newPath] = folded }
    }

    // MARK: Trash

    /// Moves files to `.trash/`; a project takes its tasks. The selection moves to the next file in the list.
    func moveToTrash(_ paths: [String]) async {
        let items = paths.compactMap { index[$0] }
        guard let vault, let item = items.first else { return }
        let index = index
        let affected = items.flatMap { [$0.path] + ($0.properties.kind == .project ? index.tasks(in: $0).map(\.path) : []) }
        if let document, affected.contains(document.path) {
            await save(document)
            guard !document.isDirty else {
                errorMessage = "“\(Item.title(ofPath: document.path))” changed outside Ta Da. Choose which version to keep before deleting it."
                return
            }
        }
        let next = nextSelection(skipping: affected)
        do {
            let moved = try await Self.run {
                var moved: [String] = []
                for item in items where !moved.contains(item.path) { moved += try vault.moveToTrash(item.path, index: index) }
                return moved
            }
            updateIndex { for path in moved { $0.remove(path) } }
            multiSelection.subtract(moved)
            if case let .project(path) = domain, moved.contains(path) {
                domain = .today
            } else if let selection, moved.contains(selection) {
                self.selection = next
            }
        } catch {
            let name = items.count == 1 ? "“\(item.title)”" : "the files"
            errorMessage = Self.couldNot("move \(name) to the trash", error)
        }
        await refresh()
    }

    /// Moves trashed files back to `tasks/` and `projects/`; a project brings its trashed tasks.
    func restore(_ paths: Set<String>) async {
        guard let vault else { return }
        let paths = Array(paths)
        do {
            let restored = try await Self.run { try vault.restore(paths) }
            let folders = Set(restored.map { Vault.folder(of: $0) + "/" }).sorted()
            trashNote = "\(restored.count == 1 ? "1 item" : "\(restored.count) items") restored to \(folders.joined(separator: " and "))"
        } catch {
            errorMessage = Self.couldNot("restore the files", error)
        }
        trashSelection.subtract(paths)
        await refresh()
    }

    /// Moves trashed files to the Mac’s Trash; a project takes its trashed tasks.
    func discard(_ paths: Set<String>) async {
        guard let vault else { return }
        let paths = Array(paths)
        do {
            try await Self.run { try vault.discard(paths) }
        } catch {
            errorMessage = Self.couldNot("move the files to the Trash", error)
        }
        trashSelection.subtract(paths)
        trashNote = nil
        await refresh()
    }

    func emptyTrash() async {
        await discard(Set(trash.map(\.id)))
    }

    /// ⌫ or ⌘⌫ while a list has the keyboard: moves the selected files to the trash. In Trash, ⌘⌫ restores
    /// the picked files. False when there's nothing to act on.
    func deleteKey(command: Bool) -> Bool {
        if domain == .trash, !isSearching {
            guard command, !trashSelection.isEmpty else { return false }
            let paths = trashSelection
            Task { await restore(paths) }
            return true
        }
        let paths = selection.map { [$0] } ?? Array(multiSelection)
        guard !paths.isEmpty else { return false }
        Task { await moveToTrash(paths) }
        return true
    }

    /// ⌥⌘⌫ in Trash: moves the picked files to the Mac’s Trash.
    func deleteForeverKey() -> Bool {
        guard domain == .trash, !isSearching, !trashSelection.isEmpty else { return false }
        let paths = trashSelection
        Task { await discard(paths) }
        return true
    }

    /// The file after the selection in the list on screen that isn't in `removed`, else the one before it.
    private func nextSelection(skipping removed: [String]) -> String? {
        guard let selection, let paths = arrowKeyList?.paths, let i = paths.firstIndex(of: selection) else { return nil }
        return paths[(i + 1)...].first { !removed.contains($0) } ?? paths[..<i].last { !removed.contains($0) }
    }

    // MARK: Move and dates

    /// The files a due date or deadline is set on, in list order. With `path` (a right-clicked or dragged row): the
    /// picked tasks when it's one of them, else just it. Without: the picked tasks, else the open file.
    func dateTargets(for path: String? = nil) -> [String] {
        let paths: Set<String>
        if let path {
            paths = multiSelection.contains(path) ? multiSelection : [path]
        } else {
            paths = multiSelection.isEmpty ? Set([selection].compactMap { $0 }) : multiSelection
        }
        let order = arrowKeyList?.paths ?? []
        return paths.filter { index[$0] != nil }
            .sorted { (order.firstIndex(of: $0) ?? .max, $0) < (order.firstIndex(of: $1) ?? .max, $1) }
    }

    /// The tasks a move acts on: `dateTargets(for:)` without projects.
    func moveTargets(for path: String? = nil) -> [String] {
        dateTargets(for: path).filter { index[$0]?.properties.kind == .task }
    }

    /// ⇧⌘M: asks for the project menu for the move targets, under the open task's project chip or the first
    /// picked row.
    func showMoveMenu() {
        requestMenu(.project, for: moveTargets())
    }

    /// ⌘S (due date) and ⌘D (deadline): asks for `kind`'s calendar for the date targets, under the open file's
    /// date chip or the first picked row.
    func showDateMenu(_ kind: AgendaEntry.Kind) {
        requestMenu(.date(kind), for: dateTargets())
    }

    private func requestMenu(_ menu: PropertyMenuRequest.Menu, for paths: [String]) {
        guard let first = paths.first else { return }
        propertyMenuRequest = PropertyMenuRequest(menu: menu, paths: paths, anchor: first, onChip: selection == first)
    }

    /// Links the tasks at `paths` to `project`, or empties their `project:` when it's nil. Tasks already there
    /// aren't written.
    func setProject(_ project: Item?, of paths: [String]) async {
        for path in paths {
            guard let task = index[path] else { continue }
            if let project {
                if index.project(of: task)?.path != project.path {
                    await setProperty("project", to: .link(title: project.title), in: path)
                }
            } else if task.properties.project != nil {
                await setProperty("project", to: nil, in: path)
            }
        }
    }

    /// Sets `kind`'s date of the files at `paths`, or empties it when `date` is nil. Files already on it aren't
    /// written.
    func setDate(_ kind: AgendaEntry.Kind, to date: LocalDate?, of paths: [String]) async {
        for path in paths {
            guard let item = index[path], item.properties[keyPath: kind.date] != date else { continue }
            await setProperty(kind.key, to: date.map { .date($0) }, in: path)
        }
    }

    /// Makes the tasks at `paths` due today. Tasks already due today aren't written.
    func makeDueToday(_ paths: [String]) async {
        let today = today
        for path in paths where index[path]?.properties.dueDate != today {
            await setProperty("dueDate", to: .date(today), in: path)
        }
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
        titleFocus = path
        if project == nil, domain != .today { domain = .loose }
        selection = path
    }

    /// Creates a task linked to `project` without opening it, its title ready to type in the project page's table.
    /// Returns the new file's path.
    @discardableResult
    func newLinkedTask(in project: Item) async -> String? {
        guard let path = await create(NewFile.task(project: project.title, today: today), in: Vault.taskFolder) else { return nil }
        titleFocus = path
        return path
    }

    /// Creates an untitled project and opens its page with its title ready to type.
    func newProject() async {
        guard let path = await create(NewFile.project(today: today), in: Vault.projectFolder) else { return }
        titleFocus = path
        open(path)
    }

    /// Creates a project called `title` and links the tasks at `paths` to it.
    func newProject(named title: String, linking paths: [String]) async {
        guard let path = await create(NewFile.project(today: today), in: Vault.projectFolder, title: title),
              let project = index[path] else { return }
        await setProject(project, of: paths)
    }

    private func create(_ text: String, in folder: String, title: String = "Untitled") async -> String? {
        guard let vault else { return nil }
        do {
            let path = try await Self.run { try vault.create(text, in: folder, title: title) }
            if let item = Item(parsing: text, path: path) { updateIndex { $0.update(item) } }
            return path
        } catch {
            errorMessage = Self.couldNot("create a file in “\(folder)”", error)
            return nil
        }
    }

    // MARK: Lists

    /// The lists the sidebar and browser show, worked out once per change to the index or the date.
    private(set) var todayTasks: [Item] = []
    private(set) var looseTasks: [Item] = []
    private(set) var upcoming: [AgendaEntry] = []
    /// Active projects with their progress.
    private(set) var projects: [ProjectProgress] = []

    var todayCount: Int { todayTasks.count { $0.properties.status != .done } }
    var looseCount: Int { looseTasks.count }

    /// Changes the index, then the lists. Several changes in one call update the lists once.
    private func updateIndex(_ change: (inout VaultIndex) -> Void) {
        change(&index)
        updateLists()
    }

    /// Puts an edited item in the index. When its properties are unchanged, as when typing in its body,
    /// the lists keep their order and take the new item in place of the old.
    private func updateIndex(replacing item: Item) {
        guard index[item.path]?.properties == item.properties else { return updateIndex { $0.update(item) } }
        index.update(item)
        if let i = todayTasks.firstIndex(where: { $0.path == item.path }) { todayTasks[i] = item }
        if let i = looseTasks.firstIndex(where: { $0.path == item.path }) { looseTasks[i] = item }
        for i in upcoming.indices where upcoming[i].item.path == item.path { upcoming[i].item = item }
        if let i = projects.firstIndex(where: { $0.project.path == item.path }) { projects[i].project = item }
    }

    /// Assigning a list equal to the old one doesn't notify the views that show it.
    private func updateLists() {
        todayTasks = index.today(today)
        looseTasks = index.loose()
        upcoming = index.upcoming(after: today)
        projects = index.activeProjects()
    }

    var folderDisplayName: String { vault.map { Self.displayName(for: $0.root) } ?? "" }

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
