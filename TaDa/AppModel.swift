// The app's root state: the chosen folder, its index, the sidebar selection, the open document and the theme.
import Foundation
import TaDaCore

@Observable final class AppModel {
    enum Domain: Hashable {
        case today, upcoming, loose, logbook, trash
        /// A project, by vault-relative path.
        case project(String)
        /// An area, by vault-relative path.
        case area(String)
        /// A tag's page, by the tag's path (lowercased); nil for Untagged.
        case tag(String?)
    }

    /// What the sidebar lists under Trash: the area and project hierarchy, or the tag tree.
    enum SidebarMode: String {
        case projects, tags
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
            switch domain {
            case .tag: sidebarMode = .tags
            case .loose, .project, .area: sidebarMode = .projects
            default: break
            }
            updateTagPage()
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
    /// The last pasted image's save, which waits for the ones before it.
    @ObservationIgnored private(set) var savingImage: Task<Void, Never>?
    @ObservationIgnored private var imageSaves = 0
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
    /// Bumped by the Toggle Sidebar command; the window shows, hides or floats the sidebar.
    var sidebarToggleRequest = 0
    /// The browser list on screen, top to bottom, for the arrow keys and selection clicks. Set by the list itself.
    struct ArrowKeyList: Equatable {
        var id: UUID
        var paths: [String]
        /// Shift- and ⌘-click pick several tasks.
        var allowsMultipleSelection = false
    }
    @ObservationIgnored var arrowKeyList: ArrowKeyList?
    /// The folder's images, most recently changed first: what `![[` lists and embeds draw from.
    private(set) var attachments: [String] = []
    /// The Ta Da files in `.trash/`, most recently deleted first.
    private(set) var trash: [TrashedItem] = []
    /// The images in `.trash/attachments/`, most recently deleted first.
    private(set) var trashedAttachments: [TrashedAttachment] = []
    /// The image the embed menu asked to rename or delete; the window shows its dialog.
    var imageDialog: ImageDialog?
    enum ImageDialog: Identifiable, Equatable {
        case rename(String)
        case delete(String)

        var path: String {
            switch self {
            case .rename(let path), .delete(let path): path
            }
        }
        var id: String { "\(self)" }
    }
    /// The files picked in the Trash list, by path.
    var trashSelection: Set<String> = []
    /// What the last restore did, shown in Trash.
    var trashNote: String?
    /// The file whose file menu is open; its row is ringed.
    var menuTarget: String?
    /// ⇧⌘M's request for the project or area menu, or ⌘S's and ⌘D's for a date's calendar. The view it names opens the
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
            case area
            case date(AgendaEntry.Kind)
        }
    }
    /// Deleting an area, or files that embed images, waits here for the user to confirm; `confirmTrash(_:images:)`
    /// goes ahead.
    var trashConfirmation: TrashConfirmation?
    struct TrashConfirmation: Equatable, Identifiable {
        let id = UUID()
        /// The files to delete, as asked.
        let paths: [String]
        /// Those files, as they were when asked about.
        let items: [Item]
        /// How many files go: those and everything they take.
        let count: Int
        /// The images the files embed, each under the first file that embeds it; empty when they embed none.
        var images: [TrashImageGroup] = []
    }
    /// A file going to the trash and the images listed under it.
    struct TrashImageGroup: Equatable {
        let item: Item
        let images: [TrashImage]
    }
    /// An image a file going to the trash embeds, with the titles of the other files that embed it.
    struct TrashImage: Equatable {
        let path: String
        /// Files that stay, whose embeds would show it as missing.
        let keptIn: [String]
        /// Other files going to the trash.
        let goingIn: [String]
    }
    /// Completing a project that still has open tasks, or logging one with Log Now, waits here for the user to choose
    /// whether its open tasks are completed or cancelled; `answerCompletion(_:tasksAs:)` goes ahead.
    var completionConfirmation: CompletionConfirmation?
    /// Further questions, as when several projects are completed at once; each is shown once the one before is answered.
    private var pendingCompletions: [CompletionConfirmation] = []
    struct CompletionConfirmation: Equatable, Identifiable {
        let id = UUID()
        let project: Item
        /// Done or Cancelled: what the project is set to.
        let status: Status
        /// The project's open tasks, as they were when asked about; answering sets those it has then.
        let tasks: [Item]
        /// Log Now asked; it goes on logging once this is answered.
        var logsAfter = false
    }
    /// Whether `VaultWatcher` is watching the folder. Without it, changes are picked up when the app becomes active.
    private(set) var isWatching = false
    /// Whether the folder is in iCloud Drive, or in an app's iCloud folder such as Obsidian's.
    private(set) var isInICloud = false
    /// Refreshed when the day changes, so every query uses the same `today`.
    var today = LocalDate(Date()) {
        didSet {
            guard today != oldValue else { return }
            updateLists()
            Task { await logIfDue() }
        }
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
    /// Haptic feedback on iOS; Settings ▸ Haptics turns it off.
    var haptics: Bool {
        didSet { defaults.set(!haptics, forKey: Keys.hapticsOff) }
    }
    /// The task groups folded in each project's or area's browser ("Open", "Completed"), by its path.
    private(set) var foldedGroups: [String: [String]] {
        didSet { defaults.set(foldedGroups, forKey: Keys.foldedGroups) }
    }
    /// The sidebar's Projects | Tags switch.
    var sidebarMode: SidebarMode {
        didSet { defaults.set(sidebarMode.rawValue, forKey: Keys.sidebarMode) }
    }
    /// The tag tree's folded parents, by tag path.
    private(set) var foldedTags: Set<String> {
        didSet { defaults.set(foldedTags.sorted(), forKey: Keys.foldedTags) }
    }
    /// The files opened last, most recent first, for the link menu's Recent: eight besides the open one.
    private(set) var recentFiles: [String] {
        didSet { defaults.set(recentFiles, forKey: Keys.recentFiles) }
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

    func isTagFolded(_ path: String) -> Bool {
        foldedTags.contains(path)
    }

    func toggleTagFolded(_ path: String) {
        if foldedTags.remove(path) == nil { foldedTags.insert(path) }
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
        static let hapticsOff = "hapticsOff"
        static let recentFiles = "recentFiles"
        static let sidebarMode = "sidebarMode"
        static let foldedTags = "foldedTags"
        static let lastLogged = "lastLogged"
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
        haptics = !defaults.bool(forKey: Keys.hapticsOff)
        recentFiles = defaults.stringArray(forKey: Keys.recentFiles) ?? []
        sidebarMode = defaults.string(forKey: Keys.sidebarMode).flatMap(SidebarMode.init) ?? .projects
        foldedTags = Set(defaults.stringArray(forKey: Keys.foldedTags) ?? [])
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
        trashedAttachments = await Self.run { vault.trashedAttachments() }
        attachments = await Self.run { vault.attachmentPaths() }
        isInICloud = await Self.run { FileManager.default.isUbiquitousItem(at: vault.root) }
        state = .ready
        #if os(iOS)
        await Self.run { vault.downloadPlaceholders() }
        #endif
        startWatching(vault)
        await logIfDue()
    }

    private func startWatching(_ vault: Vault) {
        watcher = VaultWatcher(root: vault.root) { [weak self] in
            Task { await self?.refresh() }
        }
        isWatching = watcher != nil
    }

    #if os(iOS)
    /// Whether the app is in the background, where it can't answer file coordination.
    @ObservationIgnored private var isInBackground = false

    /// Saves unsaved edits, then stops presenting the folder and the open file, which a suspended app
    /// couldn't answer for.
    func enterBackground() async {
        isInBackground = true
        if document?.isDirty == true { await saveBeforeQuitting() }
        guard isInBackground else { return }
        watcher = nil
        present(nil)
    }

    /// Presents the folder and the open file again, and refreshes.
    func becomeActive() async {
        isInBackground = false
        if let vault, state == .ready {
            if watcher == nil { startWatching(vault) }
            if presenter == nil { present(document) }
        }
        await refresh()
    }
    #endif

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
                trashedAttachments = await Self.run { vault.trashedAttachments() }
                trashSelection.formIntersection(trash.map(\.id) + trashedAttachments.map(\.id))
                let attachments = await Self.run { vault.attachmentPaths() }
                if attachments != self.attachments { self.attachments = attachments }
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

    /// Shows a file: a project or area opens as its own page in its domain; a task opens beside the current list.
    func open(_ path: String) {
        guard let item = index[path] else { return }
        switch item.properties.kind {
        case .project: domain = .project(path)
        case .area: domain = .area(path)
        case .task: break
        }
        selection = path
    }

    /// Follows a link to a file: a logged file opens in the Logbook; a project or area opens as its own page; a task
    /// opens in its project's or area's page, or in Loose tasks.
    func openLink(to path: String) {
        guard let item = index[path] else { return }
        if item.isLogged {
            domain = .logbook
            selection = path
            return
        }
        if item.properties.kind == .task {
            let parent = index.parent(of: item)
            domain = switch parent?.properties.kind {
            case .project: .project(parent!.path)
            case .area: .area(parent!.path)
            default: .loose
            }
        }
        open(path)
    }

    /// The path of the project or area whose page is showing.
    var domainPath: String? {
        switch domain {
        case let .project(path), let .area(path): path
        default: nil
        }
    }

    /// The project or area whose page is showing.
    var domainParent: Item? { domainPath.flatMap { index[$0] } }

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
            recentFiles = Array(([path] + recentFiles.filter { $0 != path }).prefix(9))
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
        #if os(iOS)
        if isInBackground { return }  // `becomeActive` presents again
        #endif
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

    /// Saves the open document before the app quits or goes to the background, after any save already under way.
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

    /// Completes an open task or reopens a done or cancelled one. Only `status` and `completedDate` change. A project
    /// goes through `setStatus(_:in:)`, which asks first when it has open tasks.
    func toggleCompletion(_ item: Item) async {
        if item.properties.kind == .project {
            return await setStatus(item.properties.status.isClosed ? .notStarted : .done, in: item.path)
        }
        let today = today, fallback = item.properties.status
        await edit(item.path) { text in
            Completion.toggle(Item(parsing: text, path: item.path)?.properties.status ?? fallback, in: text, today: today)
        }
        await reopenParent(of: item.path, wasClosed: item.properties.status.isClosed)
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

    /// Sets the status; Done and Cancelled also set `completedDate`, anything else clears it. Unless `confirmed`,
    /// completing or cancelling a project that has open tasks asks first through `completionConfirmation`. A reopened task
    /// sets its Done or Cancelled project to Doing; a logged file that's reopened goes back to `tasks/` or `projects/`.
    func setStatus(_ status: Status, in path: String, confirmed: Bool = false) async {
        if !confirmed, status.isClosed, let item = index[path], item.properties.kind == .project {
            let tasks = index.openTasks(in: item)
            if !tasks.isEmpty {
                ask(CompletionConfirmation(project: item, status: status, tasks: tasks))
                return
            }
        }
        let today = today, wasClosed = index[path]?.properties.status.isClosed ?? false
        await edit(path) { Completion.setStatus(status, in: $0, today: today) }
        await reopenParent(of: path, wasClosed: wasClosed)
    }

    /// Shows `request`, or keeps it pending behind the question already showing.
    private func ask(_ request: CompletionConfirmation) {
        if completionConfirmation == nil { completionConfirmation = request } else { pendingCompletions.append(request) }
    }

    /// Answers `completionConfirmation`: sets the project's status and the open tasks it has now to `tasksAs` (Done or
    /// Cancelled), or leaves them all when it's nil. Log Now then goes on, and the next pending question shows.
    func answerCompletion(_ request: CompletionConfirmation, tasksAs status: Status?) async {
        if completionConfirmation?.id == request.id { completionConfirmation = nil }
        if let status, let project = index[request.project.path] {
            let tasks = index.openTasks(in: project)
            if project.properties.status != request.status {
                await setStatus(request.status, in: project.path, confirmed: true)
            }
            for task in tasks { await setStatus(status, in: task.path) }
        }
        if request.logsAfter { await logNow(asking: status != nil) }
        if completionConfirmation == nil, !pendingCompletions.isEmpty { completionConfirmation = pendingCompletions.removeFirst() }
    }

    /// Renames a file from a new title, and points the `[[ ]]` links to it in other files' bodies at the new title.
    /// Renaming a project also rewrites the `project:` link in its tasks; renaming an area, the `area:` link in its
    /// projects and tasks.
    func rename(_ path: String, to title: String) async {
        guard let vault, Item.title(ofPath: path) != title else { return }
        // Saved first, so a relink of the open file below reloads it without losing edits.
        if let document {
            await save(document)
            guard document.path != path || !document.isDirty else {
                errorMessage = "“\(Item.title(ofPath: path))” changed outside Ta Da. Choose which version to keep before renaming it."
                return
            }
        }
        let linkers = index[path].map { index.backlinks(to: $0).map(\.path) } ?? []
        let linksToItself = index[path]?.links.contains { $0.title.lowercased() == Item.title(ofPath: path).lowercased() } == true
        do {
            let index = index, presenter = presenter
            let kind = index[path]?.properties.kind
            // The new path, the renamed file and its relinked files as they now are, and the files that couldn't be relinked.
            let (newPath, items, failed) = try await Self.run { () throws -> (String, [Item], [String]) in
                let result: (path: String, relinked: [Item], failed: [String]) = switch kind {
                case .project: try vault.renameProject(at: path, to: title, index: index)
                case .area: try vault.renameArea(at: path, to: title, index: index)
                case .task, nil: (path: try vault.rename(path, to: title), relinked: [], failed: [])
                }
                return (result.path, try [vault.load(result.path, presenter: presenter)].compactMap { $0 } + result.relinked, result.failed)
            }
            guard newPath != path else { return }
            follow(path, to: newPath, items: items)
            if let document, items.contains(where: { $0.path == document.path }) { await reload(document, from: vault) }
            await relinkBodies(linkers + (linksToItself ? [newPath] : []), from: Item.title(ofPath: path), to: Item.title(ofPath: newPath))
            if !failed.isEmpty {
                let names = failed.map { "“\(Item.title(ofPath: $0))”" }.formatted()
                errorMessage = "Ta Da renamed “\(Item.title(ofPath: path))” to “\(Item.title(ofPath: newPath))”, but the \(kind == .area ? "area" : "project") link in \(names) still points to the old name."
            }
        } catch {
            errorMessage = Self.couldNot("rename “\(Item.title(ofPath: path))”", error)
        }
    }

    /// Points the `[[ ]]` links to `old` in `paths`' bodies at `new`, the open file's in place, unless another file in
    /// the folder, Ta Da's or not, is still named `old`.
    private func relinkBodies(_ paths: [String], from old: String, to new: String) async {
        guard let vault, old.lowercased() != new.lowercased(), index.items(titled: old).isEmpty else { return }
        let named = await Self.run { vault.markdownPaths().contains { Item.title(ofPath: $0).lowercased() == old.lowercased() } }
        guard !named else { return }
        for path in paths {
            await edit(path) { Vault.retargetLinks(in: $0, from: old, to: new) }
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
        if domain == .area(path) { domain = .area(newPath) }
        if selection == path || selection == nil && (domain == .project(newPath) || domain == .area(newPath)) { selection = newPath }
        if let folded = foldedGroups.removeValue(forKey: path) { foldedGroups[newPath] = folded }
        if recentFiles.contains(path) { recentFiles = recentFiles.map { $0 == path ? newPath : $0 } }
    }

    // MARK: Attachments

    /// An image pasted or dropped into the editor.
    enum PastedImage {
        /// An image file: one in the folder is embedded where it is; another is copied into `attachments/`.
        case file(URL)
        /// Image data without a file, saved as `Pasted image <time>.<ext>`.
        case data(Data, extension: String)
    }

    /// Saves a pasted or dropped image into `attachments/`, numbering a taken name, and returns its `![[ ]]`. An image
    /// already in the folder isn't copied. The file is written off the main actor, in order (`savingImage` finishes
    /// when they all are). Nil when it can't be saved, with the reason in `errorMessage`.
    func embed(_ image: PastedImage) -> String? {
        guard let vault else { return nil }
        let taken = Set(attachments.filter { Vault.folder(of: $0) == Vault.attachmentFolder }.map { String($0.split(separator: "/").last ?? "") })
        let path: String
        var save: (@Sendable () throws -> Void)?
        switch image {
        case .file(let url):
            let root = vault.root.resolvingSymlinksInPath().pathComponents
            let components = url.resolvingSymlinksInPath().pathComponents
            let relative = components.dropFirst(root.count)
            if components.starts(with: root), !relative.isEmpty, !relative.contains(where: { $0.hasPrefix(".") }) {
                path = relative.joined(separator: "/")
            } else {
                path = Vault.attachmentPath(named: url.lastPathComponent, avoiding: taken)
                save = { try vault.saveAttachment(Data(contentsOf: url), at: path) }
            }
        case .data(let data, let ext):
            path = Vault.attachmentPath(named: FileNaming.pastedImage(at: Date(), extension: ext), avoiding: taken)
            save = { try vault.saveAttachment(data, at: path) }
        }
        if !attachments.contains(path) { attachments.insert(path, at: 0) }
        if let save {
            let previous = savingImage
            imageSaves += 1
            savingImage = Task {
                await previous?.value
                do {
                    try await Self.run(save)
                } catch {
                    attachments.removeAll { $0 == path }
                    errorMessage = Self.couldNot("save the image", error)
                }
                imageSaves -= 1
                if imageSaves == 0 { attachments = await Self.run { vault.attachmentPaths() } }
            }
        }
        return "![[\(Vault.embedTarget(for: path, in: attachments))]]"
    }

    /// The image an embed shows, from the text between `![[` and `]]`.
    func attachmentPath(forEmbed name: String) -> String? {
        WikiLink(inner: name).flatMap { Vault.attachmentPath(for: $0, in: attachments) }
    }

    /// The files whose embeds show the image at `path`, the open one first, with how many times each embeds it.
    func embedders(ofAttachment path: String) -> [(item: Item, count: Int)] {
        let embedders = index.embedders(ofAttachment: path, among: attachments)
        return embedders.filter { $0.item.path == document?.path } + embedders.filter { $0.item.path != document?.path }
    }

    /// Renames an image in its folder (keeping its extension) and points every `![[ ]]` that showed it at the new
    /// name, the open file's in place.
    func renameAttachment(_ path: String, to name: String) async {
        guard let vault else { return }
        let newPath = Vault.renamedAttachment(path, to: name), oldName = Item.title(ofPath: path)
        guard newPath != path else { return }
        guard !Vault.attachmentName(of: newPath, isTakenBesides: path, in: attachments) else {
            errorMessage = "An image named “\(Item.title(ofPath: newPath))” is already in the folder."
            return
        }
        let paths = attachments
        let files = Set(index.embedders(ofAttachment: path, among: paths).map(\.item.path) + [document?.path].compactMap { $0 })
        do {
            try await Self.run { try vault.renameAttachment(path, to: newPath) }
        } catch {
            errorMessage = Self.couldNot("rename “\(oldName)”", error)
            return
        }
        attachments = attachments.map { $0 == path ? newPath : $0 }
        for file in files.sorted() {
            await edit(file) { Vault.retargetEmbeds(in: $0, from: path, to: newPath, paths: paths) }
        }
    }

    /// Moves an image to `.trash/attachments/`. The files that embed it keep their `![[ ]]`, which shows as missing
    /// until the image is restored.
    func trashAttachment(_ path: String) async {
        guard let vault else { return }
        do {
            _ = try await Self.run { try vault.moveAttachmentsToTrash([path]) }
        } catch {
            errorMessage = Self.couldNot("move “\(Item.title(ofPath: path))” to the trash", error)
        }
        await refresh()
    }

    // MARK: Trash

    /// Moves files to `.trash/`; a project takes its tasks, an area its projects and all their tasks, and `images` go to
    /// `.trash/attachments/`. Unless `confirmed`, deleting an area or files that embed images asks first through
    /// `trashConfirmation`. The selection moves to the next file in the list.
    func moveToTrash(_ paths: [String], confirmed: Bool = false, images: [String] = []) async {
        let items = paths.compactMap { index[$0] }
        guard let vault, let item = items.first else { return }
        let affected = filesTrashed(with: items)
        if let document, affected.contains(where: { $0.path == document.path }) {
            await save(document)
            guard !document.isDirty else {
                errorMessage = "“\(Item.title(ofPath: document.path))” changed outside Ta Da. Choose which version to keep before deleting it."
                return
            }
        }
        if !confirmed {
            let groups = imageGroups(trashedWith: affected)
            if !groups.isEmpty || items.contains(where: { $0.properties.kind == .area }) {
                trashConfirmation = TrashConfirmation(paths: paths, items: items, count: affected.count, images: groups)
                return
            }
        }
        let next = nextSelection(skipping: affected.map(\.path))
        let index = index
        do {
            let moved = try await Self.run {
                var moved: [String] = []
                for item in items where !moved.contains(item.path) { moved += try vault.moveToTrash(item.path, index: index) }
                return moved
            }
            updateIndex { for path in moved { $0.remove(path) } }
            multiSelection.subtract(moved)
            if let path = domainPath, moved.contains(path) {
                domain = .today
            } else if let selection, moved.contains(selection) {
                self.selection = next
            }
            do {
                _ = try await Self.run { try vault.moveAttachmentsToTrash(images) }
            } catch {
                errorMessage = Self.couldNot("move the images to the trash", error)
            }
        } catch {
            let name = items.count == 1 ? "“\(item.title)”" : "the files"
            errorMessage = Self.couldNot("move \(name) to the trash", error)
        }
        await refresh()
    }

    /// Deletes the files `request` asked about, and `images`. An alert has already cleared `trashConfirmation` by the
    /// time its button's task runs, so the request comes from the alert.
    func confirmTrash(_ request: TrashConfirmation, images: [String] = []) async {
        if trashConfirmation?.id == request.id { trashConfirmation = nil }
        await moveToTrash(request.paths, confirmed: true, images: images)
    }

    /// Whether deleting `paths` asks first: an area does, and so do files that embed images.
    func asksBeforeTrashing(_ paths: [String]) -> Bool {
        let items = paths.compactMap { index[$0] }
        return items.contains { $0.properties.kind == .area } || !imageGroups(trashedWith: filesTrashed(with: items)).isEmpty
    }

    /// `items` and the files each takes to the trash: a project its tasks, an area its projects and all their tasks.
    private func filesTrashed(with items: [Item]) -> [Item] {
        var files: [Item] = []
        for item in items {
            let taken = switch item.properties.kind {
            case .task: [item]
            case .project: [item] + index.tasks(in: item)
            case .area: [item] + index.projects(in: item) + index.allTasks(in: item)
            }
            for file in taken where !files.contains(where: { $0.path == file.path }) { files.append(file) }
        }
        return files
    }

    /// The images `files` embed, each under the first file that embeds it, with the other files that embed it.
    private func imageGroups(trashedWith files: [Item]) -> [TrashImageGroup] {
        let going = Set(files.map(\.path)), attachments = attachments
        var listed: Set<String> = []
        return files.compactMap { item in
            let paths = item.embeds.compactMap { Vault.attachmentPath(for: $0, in: attachments) }.filter { listed.insert($0).inserted }
            let images = paths.map { path in
                let others = index.embedders(ofAttachment: path, among: attachments).map(\.item).filter { $0.path != item.path }
                return TrashImage(path: path, keptIn: others.filter { !going.contains($0.path) }.map(\.title),
                                  goingIn: others.filter { going.contains($0.path) }.map(\.title))
            }
            return images.isEmpty ? nil : TrashImageGroup(item: item, images: images)
        }
    }

    /// Moves trashed files back to `tasks/`, `projects/` and `areas/`, each bringing back its parents.
    func restore(_ paths: Set<String>) async {
        guard let vault else { return }
        let paths = Array(paths)
        do {
            let index = index, today = today
            let restored = try await Self.run { try vault.restore(paths, index: index, today: today) }
            let folders = Set(restored.map { Vault.folder(of: $0) + "/" }).sorted()
            trashNote = "\(restored.count == 1 ? "1 item" : "\(restored.count) items") restored to \(folders.formatted(.list(type: .and)))"
        } catch {
            errorMessage = Self.couldNot("restore the files", error)
        }
        trashSelection.subtract(paths)
        await refresh()
    }

    /// Moves trashed files to the system Trash, or deletes them where that isn't supported; a project takes its
    /// trashed tasks, an area its trashed projects and tasks. Files that can't be removed are reported and the rest still go.
    func discard(_ paths: Set<String>) async {
        guard let vault else { return }
        let paths = Array(paths)
        do {
            let index = index
            try await Self.run { try vault.discard(paths, index: index) }
        } catch {
            errorMessage = Self.couldNot("delete the files", error)
        }
        trashSelection.subtract(paths)
        trashNote = nil
        await refresh()
    }

    /// The files and images in `.trash/`.
    var trashCount: Int { trash.count + trashedAttachments.count }

    /// The trashed images that go with each trashed file, by its path: Trash lists them under it. An image that another
    /// trashed file or a file in the folder embeds goes with none of them.
    var trashedAttachmentsByFile: [String: [TrashedAttachment]] {
        let live = Set(index.items.values.flatMap(\.embeds).compactMap { $0.attachmentName?.lowercased() })
        var byFile: [String: [TrashedAttachment]] = [:]
        for entry in trash {
            let images = TrashedAttachment.attachments(of: [entry], in: trashedAttachments, others: trash, live: live)
            if !images.isEmpty { byFile[entry.id] = images }
        }
        return byFile
    }

    /// Trashed images that go with no trashed file: Trash lists them on their own.
    var looseTrashedAttachments: [TrashedAttachment] {
        let taken = Set(trashedAttachmentsByFile.values.joined())
        return trashedAttachments.filter { !taken.contains($0) }
    }

    /// "In Photograph the Kombi, Kombi service history": the files whose embeds of a trashed image's name show as missing;
    /// nil when none does.
    func embeddersSummary(of trashed: TrashedAttachment) -> String? {
        let name = trashed.name.lowercased(), attachments = attachments
        let titles = index.embedders(of: trashed.name).filter { entry in
            entry.item.embeds.contains { $0.attachmentName?.lowercased() == name && Vault.attachmentPath(for: $0, in: attachments) == nil }
        }.map(\.item.title)
        return titles.isEmpty ? nil : "In " + titles.joined(separator: ", ")
    }

    func emptyTrash() async {
        await discard(Set(trash.map(\.id) + trashedAttachments.map(\.id)))
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

    // MARK: Logbook

    /// Logs the files completed before today, once a day: when the folder opens or the day changes. Logged files reopened
    /// in another app go back.
    /// Each folder's day is kept once its logging succeeds; after a failure the next open or day change tries again.
    func logIfDue() async {
        guard state == .ready, !isLogging, let folder = vault?.root,
              Self.lastLogged(folder, in: defaults) != today else { return }
        isLogging = true
        defer { isLogging = false }
        let day = today
        var succeeded = await log(index.filesToLog(completedBefore: day).map(\.path))
        let reopened = index.reopenedLogged.map(\.path)
        if !reopened.isEmpty {
            succeeded = await moveFiles("put back the reopened files") { try $0.unlog(reopened, index: $1, today: $2) } != nil
                && succeeded
        }
        let waiting = index.loggedProjectsWithOpenTasks
        if !waiting.isEmpty {
            let paths = waiting.map(\.path)
            let moved = await moveFiles("put back the projects with open tasks") { try $0.unlog(paths, index: $1, today: $2) }
            for path in paths { if let back = moved?[path] { await setStatus(.doing, in: back) } }
            succeeded = moved != nil && succeeded
        }
        if succeeded { Self.setLastLogged(folder, to: day, in: defaults) }
    }

    /// Whether `logIfDue()` is running.
    private var isLogging = false

    /// The day `logIfDue()` last logged `folder`.
    static func lastLogged(_ folder: URL, in defaults: any SettingsStore) -> LocalDate? {
        (defaults.dictionary(forKey: Keys.lastLogged)?[folder.resolvingSymlinksInPath().path] as? String).flatMap(LocalDate.init)
    }

    static func setLastLogged(_ folder: URL, to day: LocalDate, in defaults: any SettingsStore) {
        var days = defaults.dictionary(forKey: Keys.lastLogged) ?? [:]
        days[folder.resolvingSymlinksInPath().path] = day.description
        defaults.set(days, forKey: Keys.lastLogged)
    }

    /// Log Now: logs every completed task and project. Unless `asking` is false, a completed project that still has open
    /// tasks asks first through `completionConfirmation`, and logging goes on once it's answered; without asking it
    /// waits.
    func logNow(asking: Bool = true) async {
        if asking, let project = index.projects.sorted(by: VaultIndex.byTitle)
            .first(where: { $0.properties.status.isClosed && !index.openTasks(in: $0).isEmpty }) {
            ask(CompletionConfirmation(project: project, status: project.properties.status,
                                       tasks: index.openTasks(in: project), logsAfter: true))
            return
        }
        await log(index.filesToLog(completedBefore: nil).map(\.path))
    }

    /// Whether Log Now has anything to log or ask about.
    var hasFilesToLog: Bool { logbook.contains { !$0.isLogged } }

    /// Moves files to `.logbook/`. Returns false when that failed.
    @discardableResult
    private func log(_ paths: [String]) async -> Bool {
        guard !paths.isEmpty else { return true }
        return await moveFiles("log the files") { try $0.log(paths, index: $1, today: $2) } != nil
    }

    /// A logged file that isn't Done or Cancelled any more goes back to `tasks/` or `projects/`, bringing back its logged
    /// project as Doing. A task reopened from Done or Cancelled sets its Done or Cancelled project to Doing, and an open
    /// task whose project is logged brings it back as Doing.
    private func reopenParent(of path: String, wasClosed: Bool) async {
        guard var item = index[path], !item.properties.status.isClosed else { return }
        let wasClosed = wasClosed || item.isLogged
        if item.isLogged {
            let moved = await moveFiles("put “\(item.title)” back") { try $0.unlog([path], index: $1, today: $2) }
            guard let back = moved?[path].flatMap({ index[$0] }) else { return }
            item = back
        }
        guard let project = index.project(of: item) else { return }
        if project.isLogged {
            let moved = await moveFiles("put “\(project.title)” back") { try $0.unlog([project.path], index: $1, today: $2) }
            if let back = moved?[project.path] { await setStatus(.doing, in: back) }
        } else if wasClosed, project.properties.status.isClosed {
            await setStatus(.doing, in: project.path)
        }
    }

    /// Saves the open file, moves files with `move` (which returns each new path by its old one), and follows them.
    /// Returns the moved paths, or nil when moving failed.
    @discardableResult
    private func moveFiles(_ action: String,
                           _ move: @escaping @Sendable (Vault, VaultIndex, LocalDate) throws -> [String: String]) async
        -> [String: String]? {
        guard let vault else { return nil }
        if let document { await save(document) }
        let index = index, today = today
        var result: [String: String]?
        do {
            let moved = try await Self.run { try move(vault, index, today) }
            let items = await Self.run { moved.values.compactMap { try? vault.load($0) } }
            for (old, new) in moved { follow(old, to: new, items: items.filter { $0.path == new }) }
            result = moved
        } catch {
            errorMessage = Self.couldNot(action, error)
        }
        await refresh()
        return result
    }

    // MARK: Tags

    /// Adds a tag to the file's `tags:`. A tag it has there already, ignoring case, isn't written.
    func addTag(_ tag: Tag, to path: String) async {
        await edit(path) { FrontmatterEditor.addTag(tag, in: $0) }
    }

    /// Removes a tag from the file's `tags:`. The body's tags stay.
    func removeTag(_ tag: Tag, from path: String) async {
        await edit(path) { FrontmatterEditor.removeTag(tag, in: $0) }
    }

    /// The tag at `path` in the tag tree, spelled as the index shows it; nil when no file carries it or a child.
    func tag(at path: String) -> Tag? {
        var nodes = tagTree
        while let node = nodes.first(where: { path == $0.tag.path || path.hasPrefix($0.tag.path + "/") }) {
            if node.tag.path == path { return node.tag }
            nodes = node.children
        }
        return nil
    }

    /// The tag tree's rows, top to bottom, leaving out the children of folded parents.
    var visibleTags: [(node: TagNode, depth: Int)] {
        func rows(_ nodes: [TagNode], depth: Int) -> [(node: TagNode, depth: Int)] {
            nodes.flatMap { [($0, depth)] + (isTagFolded($0.tag.path) ? [] : rows($0.children, depth: depth + 1)) }
        }
        return rows(tagTree, depth: 0)
    }

    /// How many tags are in use, parents included.
    var tagCount: Int {
        func count(_ nodes: [TagNode]) -> Int { nodes.reduce(nodes.count) { $0 + count($1.children) } }
        return count(tagTree)
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

    /// The projects an area move acts on: `dateTargets(for:)` without tasks.
    func areaTargets(for path: String? = nil) -> [String] {
        dateTargets(for: path).filter { index[$0]?.properties.kind == .project }
    }

    /// ⇧⌘M: asks for the project menu for the move targets, under the open task's project chip or the first
    /// picked row; with no tasks to move, the area menu for the area targets.
    func showMoveMenu() {
        let tasks = moveTargets()
        if tasks.isEmpty {
            requestMenu(.area, for: areaTargets())
        } else {
            requestMenu(.project, for: tasks)
        }
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

    /// Files the tasks or projects at `paths` under `parent` (a project or an area), or under nothing when it's nil.
    /// A project only goes under an area. Files already there aren't written.
    func setParent(_ parent: Item?, of paths: [String]) async {
        let target: Parent? = switch parent?.properties.kind {
        case .project: .project(parent!.title)
        case .area: .area(parent!.title)
        case .task, nil: nil
        }
        guard parent == nil || target != nil else { return }
        for path in paths {
            guard let item = index[path], item.properties.kind != .area else { continue }
            if item.properties.kind == .project, case .project = target { continue }
            if let parent {
                guard index.parent(of: item)?.path != parent.path else { continue }
            } else {
                guard item.properties.project != nil || item.properties.area != nil else { continue }
            }
            await edit(path) { Parent.set(target, in: $0) }
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

    /// Creates an untitled task and selects it with its title ready to type. On a project's or area's page it's filed
    /// there; in Today it's due today; on a tag's page it carries the tag, and on Untagged it stays there; anywhere else
    /// it opens in Loose tasks.
    func newTask() async {
        let parent = domainParent
        var tags: [Tag] = []
        if case .tag(_?) = domain, let shownTag { tags = [shownTag] }
        var text = Self.newTask(in: parent, tags: tags, today: today)
        if parent == nil, domain == .today { text = FrontmatterEditor.set("dueDate", to: .date(today), in: text) }
        guard let path = await create(text, in: Vault.taskFolder) else { return }
        titleFocus = path
        if case .tag = domain {} else if parent == nil, domain != .today { domain = .loose }
        selection = path
    }

    /// Creates a task filed under `parent` (a project or an area) without opening it, its title ready to type in the
    /// page's list. Returns the new file's path.
    @discardableResult
    func newLinkedTask(in parent: Item) async -> String? {
        guard let path = await create(Self.newTask(in: parent, today: today), in: Vault.taskFolder) else { return nil }
        titleFocus = path
        return path
    }

    private static func newTask(in parent: Item?, tags: [Tag] = [], today: LocalDate) -> String {
        switch parent?.properties.kind {
        case .project: NewFile.task(project: parent?.title, tags: tags, today: today)
        case .area: NewFile.task(area: parent?.title, tags: tags, today: today)
        case .task, nil: NewFile.task(tags: tags, today: today)
        }
    }

    /// Creates an untitled project, in the area whose page is showing, and opens its page with its title ready to type.
    func newProject() async {
        let area = domainParent.flatMap { $0.properties.kind == .area ? $0 : nil }
        guard let path = await create(NewFile.project(area: area?.title, today: today), in: Vault.projectFolder,
                                      taken: index.projectFilenames()) else { return }
        titleFocus = path
        open(path)
    }

    /// Creates a project called `title` and files the tasks at `paths` under it.
    func newProject(named title: String, linking paths: [String]) async {
        guard let path = await create(NewFile.project(today: today), in: Vault.projectFolder, title: title,
                                      taken: index.projectFilenames()),
              let project = index[path] else { return }
        await setParent(project, of: paths)
    }

    /// Creates an untitled area and opens its page with its title ready to type.
    func newArea() async {
        guard let path = await create(NewFile.area(today: today), in: Vault.areaFolder) else { return }
        titleFocus = path
        open(path)
    }

    /// Creates an area called `title`, which resolves every file that names it, and files the files at `paths` under
    /// it. Returns its path.
    @discardableResult
    func newArea(named title: String, filing paths: [String] = []) async -> String? {
        guard let path = await create(NewFile.area(today: today), in: Vault.areaFolder, title: title),
              let area = index[path] else { return nil }
        await setParent(area, of: paths)
        return path
    }

    private func create(_ text: String, in folder: String, title: String = "Untitled", taken: Set<String> = []) async -> String? {
        guard let vault else { return nil }
        do {
            let path = try await Self.run { try vault.create(text, in: folder, title: title, taken: taken) }
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
    /// Active projects without an area.
    private(set) var looseProjects: [ProjectProgress] = []
    /// Every area, with its active projects.
    private(set) var areas: [AreaProjects] = []
    /// The Logbook: logged tasks and projects, and the completed ones not logged yet.
    private(set) var logbook: [Item] = []
    /// Every tag in use and its parents, with counts.
    private(set) var tagTree: [TagNode] = []
    /// Areas, projects and tasks without a tag.
    private(set) var untaggedCount = 0
    /// Areas, projects and tasks with a tag.
    private(set) var taggedCount = 0
    /// The iPhone's tag screens' lists, by tag path (nil for Untagged), while each shows.
    private(set) var phoneTagPages: [String?: TagBrowser] = [:]
    /// The tag whose page shows, spelled as the index shows it, or as last shown once no file carries it; nil
    /// elsewhere and on Untagged.
    private(set) var shownTag: Tag?
    /// The lists of the tag page or Untagged, while one shows.
    private(set) var tagPage: TagBrowser?

    var todayCount: Int { todayTasks.count { !$0.properties.status.isClosed } }
    var looseCount: Int { looseTasks.count }

    /// Changes the index, then the lists. Several changes in one call update the lists once.
    private func updateIndex(_ change: (inout VaultIndex) -> Void) {
        change(&index)
        updateLists()
    }

    /// Puts an edited item in the index. When its properties are unchanged, as when typing in its body, the lists keep
    /// their order and take the new item in place of the old; a change to its tags redoes only the tag lists.
    private func updateIndex(replacing item: Item) {
        guard let old = index[item.path], old.properties == item.properties else { return updateIndex { $0.update(item) } }
        index.update(item)
        if let i = todayTasks.firstIndex(where: { $0.path == item.path }) { todayTasks[i] = item }
        if let i = looseTasks.firstIndex(where: { $0.path == item.path }) { looseTasks[i] = item }
        for i in upcoming.indices where upcoming[i].item.path == item.path { upcoming[i].item = item }
        if let i = projects.firstIndex(where: { $0.project.path == item.path }) { projects[i].project = item }
        if let i = looseProjects.firstIndex(where: { $0.project.path == item.path }) { looseProjects[i].project = item }
        if let i = logbook.firstIndex(where: { $0.path == item.path }) { logbook[i] = item }
        for i in areas.indices {
            if areas[i].area.path == item.path { areas[i].area = item }
            if let j = areas[i].projects.firstIndex(where: { $0.project.path == item.path }) { areas[i].projects[j].project = item }
        }
        if old.tags != item.tags { return updateTags() }
        func patch(_ page: TagBrowser) -> TagBrowser {
            var page = page
            func patch(_ items: inout [Item]) {
                if let i = items.firstIndex(where: { $0.path == item.path }) { items[i] = item }
            }
            patch(&page.areasAndProjects)
            patch(&page.completed)
            for i in page.groups.indices { patch(&page.groups[i].tasks) }
            return page
        }
        if let page = tagPage { tagPage = patch(page) }
        if !phoneTagPages.isEmpty { phoneTagPages = phoneTagPages.mapValues(patch) }
    }

    /// Assigning a list equal to the old one doesn't notify the views that show it.
    private func updateLists() {
        todayTasks = index.today(today)
        looseTasks = index.loose()
        upcoming = index.upcoming(after: today)
        projects = index.activeProjects()
        looseProjects = index.looseProjects()
        areas = index.areaProjects()
        logbook = index.items.values.filter { $0.properties.kind != .area && ($0.isLogged || $0.properties.status.isClosed) }
            .sorted(by: VaultIndex.byTitle)
        updateTags()
    }

    /// The tag tree, the tagged and Untagged counts and the tag pages.
    private func updateTags() {
        tagTree = index.tagTree()
        let live = index.items.values.count { !$0.isLogged }
        untaggedCount = index.items.values.count { !$0.isLogged && $0.tags.isEmpty }
        taggedCount = live - untaggedCount
        updateTagPage()
        if !phoneTagPages.isEmpty {
            phoneTagPages = Dictionary(uniqueKeysWithValues: phoneTagPages.keys.map { ($0, phoneTagPage(for: $0)) })
        }
    }

    /// Keeps the tag screen's lists for `path` (nil for Untagged) current while it shows.
    func showPhoneTagPage(_ path: String?) {
        phoneTagPages[path] = phoneTagPage(for: path)
    }

    func hidePhoneTagPage(_ path: String?) {
        phoneTagPages[path] = nil
    }

    private func phoneTagPage(for path: String?) -> TagBrowser {
        index.tagBrowser(path.flatMap { tag(at: $0) ?? Tag($0) })
    }

    private func updateTagPage() {
        guard case let .tag(path) = domain else {
            shownTag = nil
            tagPage = nil
            return
        }
        shownTag = path.flatMap { path in tag(at: path) ?? (shownTag?.path == path ? shownTag : Tag(path)) }
        tagPage = index.tagBrowser(path == nil ? nil : shownTag)
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
