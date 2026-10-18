// The app's root state: the chosen folder, its index, the sidebar selection, the open document and the theme.
import Foundation
import TaDaCore

@Observable final class AppModel {
    enum Domain: Hashable {
        case agenda, loose, logbook, trash
        /// A project, by vault-relative path.
        case project(String)
        /// An area, by vault-relative path.
        case area(String)
        /// A tag's page, by the tag's path (lowercased); nil for Untagged.
        case tag(String?)
        /// A notes folder's page, by vault-relative path; `""` for Loose, the top level.
        case folder(String)
    }

    /// The period the Agenda shows: a day, or an ISO week.
    enum AgendaSelection: Hashable {
        case day(LocalDate)
        case week(ISOWeek)
    }

    /// What the sidebar lists under Trash: the area and project hierarchy (Tasks), the tag tree, or the notes folders.
    enum SidebarMode: String {
        case projects, tags, notes
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
    var domain = Domain.agenda {
        didSet {
            guard domain != oldValue else { return }
            selection = nil
            multiSelection = []
            trashSelection = []
            trashNote = nil
            switch domain {
            case .tag: sidebarMode = .tags
            case .folder: sidebarMode = .notes
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
    /// A file whose body should take the keyboard, caret at its start, when it opens (Quick Entry's ⌘↵).
    var bodyFocus: String?
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
    /// ⌘P's request for the project or area menu, ⌘S's and ⌘D's for a date's calendar, or ⌘T's for tagMenu. The view
    /// it names opens the menu and sets this back to nil.
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
            case tags
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
            if agendaSelection == .day(oldValue) { agendaSelection = .day(today) }
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
    /// The Agenda's day or week, and whether its month is open. It opens on today.
    var agendaSelection = AgendaSelection.day(LocalDate(Date())) {
        didSet { if agendaSelection != oldValue { updateAgenda() } }
    }
    var agendaMonthOpen = false {
        didSet { if agendaMonthOpen != oldValue { updateAgenda() } }
    }
    /// Settings ▸ Daily notes: the folders daily and week notes live in, whether week notes show, and the notes whose
    /// text new daily and week notes start from, by path.
    var dailyFolder: String {
        didSet {
            defaults.set(dailyFolder, forKey: Keys.dailyFolder)
            updateAgenda()
        }
    }
    var weekFolder: String {
        didSet {
            defaults.set(weekFolder, forKey: Keys.weekFolder)
            updateAgenda()
        }
    }
    var weekNotes: Bool {
        didSet { defaults.set(!weekNotes, forKey: Keys.weekNotesOff) }
    }
    var dailyTemplate: String? {
        didSet { defaults.set(dailyTemplate, forKey: Keys.dailyTemplate) }
    }
    var weekTemplate: String? {
        didSet { defaults.set(weekTemplate, forKey: Keys.weekTemplate) }
    }
    var dailyNoteNames: DailyNoteNames { DailyNoteNames(dailyFolder: dailyFolder, weekFolder: weekFolder) }
    /// The task groups folded in each project's or area's browser ("Open", "Completed"), by its path.
    private(set) var foldedGroups: [String: [String]] {
        didSet { defaults.set(foldedGroups, forKey: Keys.foldedGroups) }
    }
    /// The sidebar's Tasks | Tags | Notes switch.
    var sidebarMode: SidebarMode {
        didSet { defaults.set(sidebarMode.rawValue, forKey: Keys.sidebarMode) }
    }
    /// The tag tree's folded parents, by tag path.
    private(set) var foldedTags: Set<String> {
        didSet { defaults.set(foldedTags.sorted(), forKey: Keys.foldedTags) }
    }
    /// The Notes tree's folded folders, by path.
    private(set) var foldedFolders: Set<String> {
        didSet { defaults.set(foldedFolders.sorted(), forKey: Keys.foldedFolders) }
    }
    /// The files opened last, most recent first, for the link menu's Recent: eight besides the open one.
    private(set) var recentFiles: [String] {
        didSet { defaults.set(recentFiles, forKey: Keys.recentFiles) }
    }
    /// The global hotkey that opens Quick Entry; nil when cleared.
    var quickEntryHotkey: Hotkey? {
        didSet { defaults.set(quickEntryHotkey?.dictionary ?? [:], forKey: Keys.quickEntryHotkey) }
    }
    /// Each grouped list's Group choice, by `GroupedList` raw value; a missing one is the list's default.
    private(set) var groupings: [String: String] {
        didSet { defaults.set(groupings, forKey: Keys.groupings) }
    }
    /// Each page's picked tags, by domain, for the session.
    private(set) var tagFilters: [Domain: TagFilter] = [:]
    /// The browser column's width on the Mac, set by dragging the rule beside it; nil until dragged.
    var browserWidth: Double? {
        didSet { defaults.set(browserWidth, forKey: Keys.browserWidth) }
    }
    /// Another app or a macOS shortcut has `quickEntryHotkey`'s keys.
    var quickEntryHotkeyTaken = false
    /// Settings ▸ Hotkeys is recording a new hotkey, so the current one is let go.
    var isRecordingHotkey = false
    /// Quick Entry's draft. Its chips and pickers edit it as the file at `quickEntryDraftPath`, which doesn't exist.
    var quickEntryDraft = QuickEntryDraft()
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

    func grouping(of list: GroupedList) -> Grouping {
        guard let stored = groupings[list.rawValue].flatMap(Grouping.init), list.groupings.contains(stored) else {
            return list.defaultGrouping
        }
        return stored
    }

    func setGrouping(_ grouping: Grouping, of list: GroupedList) {
        groupings[list.rawValue] = grouping == list.defaultGrouping ? nil : grouping.rawValue
    }

    /// Whether a section of a Status, Date or Open list is folded. Done, Cancelled and Date's Completed start
    /// folded, so a stored entry for them means opened. `list` is the project's path, or Today's or Loose's key.
    func isFolded(_ section: ListSection, by grouping: Grouping, in list: String) -> Bool {
        isFolded(section.foldName(grouping), in: list) != section.startsFolded(grouping)
    }

    func toggleFolded(_ section: ListSection, by grouping: Grouping, in list: String) {
        toggleFolded(section.foldName(grouping), in: list)
    }

    func tagFilter(on domain: Domain) -> TagFilter {
        tagFilters[domain] ?? TagFilter()
    }

    /// Picks the tag in `domain`'s filter, or unpicks it.
    func toggleFilterTag(_ path: String, on domain: Domain) {
        var filter = tagFilter(on: domain)
        if filter.picked.remove(path) == nil { filter.picked.insert(path) }
        tagFilters[domain] = filter.isActive ? filter : nil
    }

    /// The files a page's filter narrows, before filtering: what its menu lists the tags of.
    func filterItems(on domain: Domain) -> [Item] {
        switch domain {
        case .agenda: agendaTasks
        case .loose: looseTasks
        case .project(let path): index[path].map { index.tasks(in: $0) } ?? []
        case .area(let path): index[path].map { index.projects(in: $0) + index.tasks(in: $0) } ?? []
        case .folder(let path): index.notes(in: path)
        case .logbook, .trash, .tag: []
        }
    }

    func clearTagFilter(on domain: Domain) {
        tagFilters[domain] = nil
    }

    func isTagFolded(_ path: String) -> Bool {
        foldedTags.contains(path)
    }

    func toggleTagFolded(_ path: String) {
        if foldedTags.remove(path) == nil { foldedTags.insert(path) }
    }

    func isFolderFolded(_ path: String) -> Bool {
        foldedFolders.contains(path)
    }

    func toggleFolderFolded(_ path: String) {
        if foldedFolders.remove(path) == nil { foldedFolders.insert(path) }
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
        static let foldedFolders = "foldedFolders"
        static let lastLogged = "lastLogged"
        static let quickEntryHotkey = "quickEntryHotkey"
        static let browserWidth = "browserWidth"
        static let groupings = "groupings"
        static let dailyFolder = "dailyFolder"
        static let weekFolder = "weekFolder"
        static let weekNotesOff = "weekNotesOff"
        static let dailyTemplate = "dailyTemplate"
        static let weekTemplate = "weekTemplate"
    }

    init(defaults: any SettingsStore = UserDefaults.standard) {
        self.defaults = defaults
        integrations = IntegrationsStore(defaults: defaults)
        notifications = NotificationsStore(defaults: defaults)
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
        foldedFolders = Set(defaults.stringArray(forKey: Keys.foldedFolders) ?? [])
        groupings = defaults.dictionary(forKey: Keys.groupings) as? [String: String] ?? [:]
        let names = DailyNoteNames()
        dailyFolder = defaults.string(forKey: Keys.dailyFolder) ?? names.dailyFolder
        weekFolder = defaults.string(forKey: Keys.weekFolder) ?? names.weekFolder
        weekNotes = !defaults.bool(forKey: Keys.weekNotesOff)
        dailyTemplate = defaults.string(forKey: Keys.dailyTemplate)
        weekTemplate = defaults.string(forKey: Keys.weekTemplate)
        let width = defaults.double(forKey: Keys.browserWidth)
        browserWidth = width > 0 ? width : nil
        // Missing: the default. Stored `[:]`: cleared.
        if let stored = defaults.dictionary(forKey: Keys.quickEntryHotkey) {
            quickEntryHotkey = Hotkey(stored)
        } else {
            quickEntryHotkey = .quickEntryDefault
        }
        // After launch: the event store is slow to make.
        Task { updateIntegrations() }
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
        domain = .agenda
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
        knownFolders = []
        updateIndex { $0 = loaded }
        await rescanFolders(vault)
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
                await rescanFolders(vault)
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
        for path in changes.changed.keys { boxLineCache[path] = nil }
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

    /// A sidebar click on the project or area at `path`: its browser, or its file when the browser is already showing
    /// and from its file back to the browser.
    func pickProjectOrArea(_ domain: Domain) {
        switch domain {
        case let .project(path), let .area(path):
            if self.domain == domain, !isSearching {
                selection = selection == path ? nil : path
                return
            }
        default: break
        }
        show(domain)
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

    /// Shows a file: a project or area opens as its own page in its domain; a task opens beside the current list; a note
    /// opens in its folder.
    func open(_ path: String) {
        guard let item = index[path] else { return }
        switch item.properties.kind {
        case .project: domain = .project(path)
        case .area: domain = .area(path)
        case .note: domain = .folder(Vault.folder(of: path))
        case .task: break
        }
        selection = path
    }

    /// Follows a link to a file: a logged file opens in the Logbook; a project or area opens as its own page; a task
    /// opens in its project's or area's page, or in Loose tasks; a note opens in its folder.
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
        boxLineCache[document.path] = nil
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
        guard item.properties.kind != .note else { return }
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
        if editDraft(path, { $0.status = status }) { return }
        guard index[path]?.properties.kind != .note else { return }
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
                case .task, .note, nil: (path: try vault.rename(path, to: title), relinked: [], failed: [])
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
        for (old, new) in [(Domain.project(path), Domain.project(newPath)), (.area(path), .area(newPath))] {
            if let filter = tagFilters.removeValue(forKey: old) { tagFilters[new] = filter }
        }
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
                domain = .agenda
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
            case .task, .note: [item]
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

    /// Moves trashed files back to `tasks/`, `projects/` and `areas/`, each bringing back its parents, and notes back to
    /// their folders.
    func restore(_ paths: Set<String>) async {
        guard let vault else { return }
        let paths = Array(paths)
        do {
            let index = index, today = today
            let restored = try await Self.run { try vault.restore(paths, index: index, today: today) }
            let folders = Set(restored.map { Vault.folder(of: $0).isEmpty ? "the top level" : Vault.folder(of: $0) + "/" }).sorted()
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
        if editDraft(path, { if !$0.tags.contains(where: { $0.path == tag.path }) { $0.tags.append(tag) } }) { return }
        await edit(path) { FrontmatterEditor.addTag(tag, in: $0) }
    }

    /// Removes a tag from the file's `tags:`. The body's tags stay.
    func removeTag(_ tag: Tag, from path: String) async {
        if editDraft(path, { $0.tags.removeAll { $0.path == tag.path } }) { return }
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
    /// Notes are left out.
    func dateTargets(for path: String? = nil) -> [String] {
        let paths: Set<String>
        if let path {
            paths = multiSelection.contains(path) ? multiSelection : [path]
        } else {
            paths = multiSelection.isEmpty ? Set([selection].compactMap { $0 }) : multiSelection
        }
        let order = arrowKeyList?.paths ?? []
        return paths.filter { index[$0].map { $0.properties.kind != .note } ?? false }
            .sorted { (order.firstIndex(of: $0) ?? .max, $0) < (order.firstIndex(of: $1) ?? .max, $1) }
    }

    /// The tasks a move acts on: `dateTargets(for:)` without projects.
    func moveTargets(for path: String? = nil) -> [String] {
        dateTargets(for: path).filter { index[$0]?.properties.kind == .task }
    }

    /// The notes a folder move acts on: the picked notes, or the selected one.
    func noteTargets() -> [String] {
        let paths = multiSelection.isEmpty ? Set([selection].compactMap { $0 }) : multiSelection
        return paths.filter { index[$0]?.properties.kind == .note }.sorted()
    }

    /// The projects an area move acts on: `dateTargets(for:)` without tasks.
    func areaTargets(for path: String? = nil) -> [String] {
        dateTargets(for: path).filter { index[$0]?.properties.kind == .project }
    }

    /// ⌘P: asks for the project menu for the move targets, under the open task's project chip or the first
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

    /// ⌘T: asks for tagMenu for the open file, under its + Tag chip.
    func showTagMenu() {
        guard let selection, index[selection] != nil else { return }
        requestMenu(.tags, for: [selection])
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
        case .task, .note, nil: nil
        }
        guard parent == nil || target != nil else { return }
        if editDraft(paths.first, { if $0.kind == .task || target?.key != "project" { $0.parent = target } }) { return }
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
        if editDraft(paths.first, { if kind == .due { $0.dueDate = date } else { $0.deadline = date } }) { return }
        for path in paths {
            guard let item = index[path], item.properties[keyPath: kind.date] != date else { continue }
            await setProperty(kind.key, to: date.map { .date($0) }, in: path)
        }
    }

    /// The day a task made in the Agenda or dropped on it is due: the selected day, or today when a week is selected.
    var agendaDueDay: LocalDate {
        if case let .day(day) = agendaSelection { day } else { today }
    }

    /// Makes the tasks at `paths` due on `agendaDueDay`. Tasks already due then aren't written.
    func makeDueOnAgendaDay(_ paths: [String]) async {
        let day = agendaDueDay
        for path in paths where index[path]?.properties.dueDate != day {
            await setProperty("dueDate", to: .date(day), in: path)
        }
    }

    // MARK: New files

    /// ⌘N: a new note on a notes folder's page, else a new task.
    func newTaskOrNote() async {
        if case .folder = domain { await newNote() } else { await newTask() }
    }

    /// Creates an untitled task and selects it with its title ready to type. On a project's or area's page it's filed
    /// there; in the Agenda, Loose tasks and a tag's page it's filed with the selected task's project or area; in the
    /// Agenda it's due on the selected day, or today when a week is selected; on a tag's page it carries the tag, and on Untagged it stays there; anywhere else it opens in Loose
    /// tasks.
    func newTask() async {
        let parent = domainParent ?? selectedGroup
        var tags: [Tag] = []
        if case .tag(_?) = domain, let shownTag { tags = [shownTag] }
        var text = Self.newTask(in: parent, tags: tags, today: today)
        if domain == .agenda { text = FrontmatterEditor.set("dueDate", to: .date(agendaDueDay), in: text) }
        guard let path = await create(text, in: Vault.taskFolder) else { return }
        titleFocus = path
        if case .tag = domain {} else if parent == nil, domain != .agenda { domain = .loose }
        selection = path
    }

    /// In the Agenda, Loose tasks and a tag's page, the project or area of the selected task, whose group it shows in.
    private var selectedGroup: Item? {
        switch domain {
        case .agenda, .loose, .tag: break
        default: return nil
        }
        guard let task = selection.flatMap({ index[$0] }), task.properties.kind == .task else { return nil }
        return index.parent(of: task)
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
        case .task, .note, nil: NewFile.task(tags: tags, today: today)
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

    static let quickEntryDraftPath = "Quick Entry"

    /// Quick Entry's draft as an item, for its chips and menus.
    var quickEntryItem: Item {
        Item(parsing: quickEntryDraft.text(today: today), path: Self.quickEntryDraftPath)!
    }

    /// The item at `path`: the index's, or Quick Entry's draft.
    func item(at path: String) -> Item? {
        path == Self.quickEntryDraftPath ? quickEntryItem : index[path]
    }

    /// Applies a picker's edit to Quick Entry's draft when `path` is the draft's. Returns whether it was.
    private func editDraft(_ path: String?, _ change: (inout QuickEntryDraft) -> Void) -> Bool {
        guard path == Self.quickEntryDraftPath else { return false }
        change(&quickEntryDraft)
        return true
    }

    /// Writes Quick Entry's draft as a new file, numbering its name if it's taken. Returns the new path.
    func create(_ draft: QuickEntryDraft) async -> String? {
        await create(draft.text(today: today), in: draft.folder, title: draft.title,
                     taken: draft.kind == .project ? index.projectFilenames() : [])
    }

    /// The names `create(_:)` numbers a new file against, by kind: its folder's files, and for a project every project's.
    func quickEntryTakenNames() -> [Item.Kind: Set<String>] {
        var taken: [Item.Kind: Set<String>] = [:]
        for kind in [Item.Kind.task, .project, .area] {
            let folder = QuickEntryDraft().changingKind(to: kind).folder
            taken[kind] = (vault?.filenames(in: folder) ?? []).union(kind == .project ? index.projectFilenames() : [])
        }
        return taken
    }

    /// The path `create(_:)` would give the draft, given `quickEntryTakenNames()`.
    static func quickEntryPath(for draft: QuickEntryDraft, taken: [Item.Kind: Set<String>]) -> String {
        draft.folder + "/" + FileNaming.filename(for: draft.title, existing: taken[draft.kind] ?? [])
    }

    private func create(_ text: String, in folder: String, title: String = "Untitled", taken: Set<String> = []) async -> String? {
        guard let vault else { return nil }
        do {
            let path = try await Self.run { try vault.create(text, in: folder, title: title, taken: taken) }
            if let item = Item(parsing: text, path: path) { updateIndex { $0.update(item) } }
            return path
        } catch {
            errorMessage = Self.couldNot("create a file in “\(folder.isEmpty ? folderDisplayName : folder)”", error)
            return nil
        }
    }

    // MARK: Notes

    /// The folder whose page shows; `""` for Loose, nil outside Notes.
    var shownFolder: String? {
        if case let .folder(path) = domain { path } else { nil }
    }

    /// A folder whose name field should take focus (a folder just made).
    var folderNameFocus: String?
    /// Convert to Task…, Project… or Area… asked for this note; the window shows the convert sheet.
    var convertRequest: ConvertRequest?
    struct ConvertRequest: Equatable, Identifiable {
        let id = UUID()
        let path: String
        let kind: Item.Kind
    }
    /// Moving a folder to the trash waits here for the user to confirm; `confirmTrashFolder(_:)` goes ahead.
    var folderTrashConfirmation: FolderTrashConfirmation?
    struct FolderTrashConfirmation: Equatable, Identifiable {
        let id = UUID()
        let path: String
        /// The notes in it and its subfolders.
        let count: Int
    }

    /// Creates an untitled note, with `createdDate`, in the folder whose page shows (else at the top level), and opens it
    /// there with its title ready to type.
    func newNote() async {
        let folder = shownFolder ?? ""
        guard let path = await create(NewFile.note(today: today), in: folder) else { return }
        titleFocus = path
        if domain != .folder(folder) { domain = .folder(folder) }
        selection = path
    }

    /// Selects the note for a day or week, found by its name in its folder; when there is none, creates it at that name
    /// with the template's text, and its folders, and selects it. A name that's taken is never numbered.
    func openOrCreateNote(for period: AgendaSelection) async {
        let names = dailyNoteNames
        let path: String, templatePath: String?
        let found: () -> Item?
        switch period {
        case let .day(day): (path, templatePath, found) = (names.path(for: day), dailyTemplate, { self.index.dailyNote(for: day, names: names) })
        case let .week(week): (path, templatePath, found) = (names.path(for: week), weekTemplate, { self.index.weekNote(for: week, names: names) })
        }
        if let existing = found() {
            selection = existing.path
            return
        }
        guard let vault else { return }
        let folder = existingCasing(ofFolder: Vault.folder(of: path)), filename = String(path.split(separator: "/").last ?? "")
        let (template, isTaken) = await Self.run {
            (templatePath.flatMap { try? vault.read($0) },
             vault.filenames(in: folder).contains { $0.caseInsensitiveCompare(filename) == .orderedSame })
        }
        if isTaken {
            await refresh()
            selection = found()?.path ?? path
        } else if let created = await create(NewFile.dailyNote(template: template, today: today), in: folder, title: Item.title(ofPath: path)) {
            selection = created
        }
    }

    /// The checkbox lines the Agenda's note cards drew, by note path, with the item they were read for.
    @ObservationIgnored private var boxLineCache: [String: (item: Item, lines: [NoteBoxLine])] = [:]

    /// The lines of `note`'s card, if they were read for this version of it.
    func cachedBoxLines(of note: Item) -> [NoteBoxLine]? {
        boxLineCache[note.path].flatMap { $0.item == note ? $0.lines : nil }
    }

    /// The first `NoteBoxLine.limit` checkbox lines of a note, from the open document or its file, kept until the note changes.
    func boxLines(of note: Item) async -> [NoteBoxLine] {
        if let cached = cachedBoxLines(of: note) { return cached }
        let boxes = note.checkboxes, path = note.path
        let lines: [NoteBoxLine]
        if let document, document.path == path {
            lines = NoteBoxLine.lines(in: document.text, boxes: boxes)
        } else if let vault {
            lines = await Self.run { (try? vault.read(path)).map { NoteBoxLine.lines(in: $0, boxes: boxes) } ?? [] }
        } else {
            return []
        }
        if index[path] == note { boxLineCache[path] = (note, lines) }
        return lines
    }

    /// The note of a day or week, if there is one. A week's shows only while week notes are on.
    func note(for period: AgendaSelection) -> Item? {
        switch period {
        case let .day(day): index.dailyNote(for: day, names: dailyNoteNames)
        case let .week(week): weekNotes ? index.weekNote(for: week, names: dailyNoteNames) : nil
        }
    }

    /// Where the note of a day or week is, or would be made.
    func notePath(for period: AgendaSelection) -> String {
        switch period {
        case let .day(day): dailyNoteNames.path(for: day)
        case let .week(week): dailyNoteNames.path(for: week)
        }
    }

    /// `folder` as it's spelled on disk or in the notes' paths when a folder of that name exists in another case, else as given.
    private func existingCasing(ofFolder folder: String) -> String {
        var known = knownFolders.union(index.notes.map { Vault.folder(of: $0.path) })
        for path in known { known.formUnion(Self.ancestors(of: path)) }
        var resolved = ""
        for name in folder.split(separator: "/") {
            let wanted = resolved.isEmpty ? String(name) : resolved + "/" + name
            resolved = known.sorted().first { $0.caseInsensitiveCompare(wanted) == .orderedSame } ?? wanted
        }
        return resolved
    }

    private static func ancestors(of path: String) -> [String] {
        let parts = path.split(separator: "/")
        return parts.indices.dropLast().map { parts[...$0].joined(separator: "/") }
    }

    /// Creates a folder called `name` in `parent`, or the folder whose page shows (else at the top level), its name ready
    /// to type.
    func newFolder(named name: String = "Untitled folder", in parent: String? = nil) async {
        guard let vault else { return }
        let parent = parent ?? shownFolder ?? ""
        do {
            let path = try await Self.run { try vault.createFolder(named: name, in: parent) }
            knownFolders.insert(path)
            foldedFolders.remove(parent)
            updateNotes()
            folderNameFocus = path
        } catch {
            errorMessage = Self.couldNot("create a folder in “\(parent.isEmpty ? folderDisplayName : parent)”", error)
        }
    }

    /// Renames a folder; links written with its path follow it, and so do the open file, the folder page and folds.
    func renameFolder(_ path: String, to name: String) async {
        let current = String(path.split(separator: "/").last ?? "")
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, name != current else { return }
        await moveFiles(path, isFolder: true, failure: "rename “\(current)”") { vault, index, _ in
            try vault.renameFolder(path, to: name, index: index)
        }
    }

    /// Asks before moving a folder to the trash, naming how many notes go.
    func trashFolder(_ path: String) {
        folderTrashConfirmation = FolderTrashConfirmation(path: path, count: index.notes.count { $0.path.hasPrefix(path + "/") })
    }

    /// Moves the folder `request` asked about into `.trash/` whole. A folder page in it shows its parent.
    func confirmTrashFolder(_ request: FolderTrashConfirmation) async {
        if folderTrashConfirmation?.id == request.id { folderTrashConfirmation = nil }
        guard let vault else { return }
        let path = request.path
        let isInside = { (file: String) in file == path || file.hasPrefix(path + "/") }
        if let document, isInside(document.path) {
            await save(document)
            guard !document.isDirty else {
                errorMessage = "“\(Item.title(ofPath: document.path))” changed outside Ta Da. Choose which version to keep before deleting it."
                return
            }
        }
        // Before the write, as a refresh while it runs can show Loose.
        let shown = shownFolder
        do {
            _ = try await Self.run { try vault.trashFolder(path) }
        } catch {
            errorMessage = Self.couldNot("move “\(Item.title(ofPath: path))” to the trash", error)
            return
        }
        if let selection, isInside(selection) { self.selection = nil }
        knownFolders = knownFolders.filter { !isInside($0) }
        updateNotes()
        if let shown, isInside(shown) { domain = .folder(Vault.folder(of: path)) }
        await refresh()
    }

    /// Moves a note into `folder` (`""` for the top level); links written with its path follow it.
    func moveNote(_ path: String, to folder: String) async {
        await moveFiles(path, isFolder: false, failure: "move “\(Item.title(ofPath: path))”") { vault, index, _ in
            try vault.moveNote(path, to: folder, index: index)
        }
    }

    /// Converts a note to a task, project or area, filed under `parent`, and opens it in Tasks.
    func convert(_ path: String, to kind: Item.Kind, status: Status = .notStarted, parent: Parent? = nil) async {
        guard let newPath = await moveFiles(path, isFolder: false, failure: "convert “\(Item.title(ofPath: path))”", { vault, index, today in
            try vault.convert(path, to: kind, status: status, parent: parent, index: index, today: today)
        }), index[newPath]?.properties.kind == kind else { return }
        openLink(to: newPath)
    }

    /// Runs a write that moves the file at `path`, or every file in the folder at `path`, saving the open file first.
    /// The folder page, the selection, the open file, Recent and folds follow; then the index is refreshed from disk.
    /// Returns the new path; nil when it failed.
    @discardableResult
    private func moveFiles(_ path: String, isFolder: Bool, failure: String,
                           _ work: @escaping @Sendable (Vault, VaultIndex, LocalDate) throws -> Relinked) async -> String? {
        guard let vault else { return nil }
        let isInside = { (file: String) in file == path || isFolder && file.hasPrefix(path + "/") }
        if let document, isInside(document.path) {
            await save(document)
            guard !document.isDirty else {
                errorMessage = "“\(Item.title(ofPath: document.path))” changed outside Ta Da. Choose which version to keep before moving it."
                return nil
            }
        }
        // Before the write, as a refresh while it runs can clear the selection or show Loose, and before the folder page
        // changes, which clears the selection too.
        let selected = selection, shown = shownFolder
        let index = index, today = today
        let result: Relinked
        do {
            result = try await Self.run { try work(vault, index, today) }
        } catch {
            errorMessage = Self.couldNot(failure, error)
            return nil
        }
        let newPath = result.path
        guard newPath != path else { return path }
        let moved = { (file: String) in isInside(file) ? newPath + file.dropFirst(path.count) : file }
        if isFolder {
            knownFolders = Set(knownFolders.map(moved))
            foldedFolders = Set(foldedFolders.map(moved))
            for case let (.folder(old), filter) in tagFilters where isInside(old) {
                tagFilters[.folder(old)] = nil
                tagFilters[.folder(moved(old))] = filter
            }
            updateNotes()
            if let shown, isInside(shown) { domain = .folder(moved(shown)) }
        }
        let followed = document.flatMap { isInside($0.path) ? $0 : nil }
        if let followed {
            followed.path = moved(followed.path)
            followed.isRemovedOnDisk = false
        }
        if let selected, isInside(selected) { selection = moved(selected) }
        if recentFiles.contains(where: isInside) { recentFiles = recentFiles.map(moved) }
        await refresh()
        if let followed, followed === document {
            // A refresh during the write may already have seen the file at its new path, so this one didn't reload it.
            await reload(followed, from: vault)
            if followed.isDirty { await save(followed) }
            if let item = followed.item, index[item.path] != item { updateIndex { $0.update(item) } }
        }
        if !result.failed.isEmpty {
            let names = result.failed.map { "“\(Item.title(ofPath: $0))”" }.formatted()
            errorMessage = "Ta Da moved “\(Item.title(ofPath: path))”, but the links in \(names) still point to the old place."
        }
        return newPath
    }

    // MARK: Lists

    /// The lists the sidebar and browser show, worked out once per change to the index or the date.
    private(set) var todayTasks: [Item] = []
    private(set) var looseTasks: [Item] = []
    private(set) var upcoming: [AgendaEntry] = []
    /// The Agenda's tasks when a day is selected, grouped as Today's are, and its entries when a week is selected.
    private(set) var agendaTasks: [Item] = []
    private(set) var agendaWeekEntries: [AgendaEntry] = []
    /// What the days in `agendaMarksRange` show: their dots.
    private(set) var agendaMarks: [LocalDate: DayMarks] = [:]
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
    /// Areas, projects, tasks and notes without a tag.
    private(set) var untaggedCount = 0
    /// Areas, projects, tasks and notes with a tag.
    private(set) var taggedCount = 0
    /// The Notes tree, below Loose.
    private(set) var folderTree: [FolderNode] = []
    /// The notes at the top level.
    private(set) var looseNoteCount = 0
    /// Folders known to be on disk: the empty ones and those holding notes at the last scan, and the ones Ta Da made
    /// since. A folder stays in the tree when its last note goes, until a scan finds it gone.
    private var knownFolders: Set<String> = []
    /// The iPhone's tag screens' lists, by tag path (nil for Untagged), while each shows.
    private(set) var phoneTagPages: [String?: TagBrowser] = [:]
    /// The tag whose page shows, spelled as the index shows it, or as last shown once no file carries it; nil
    /// elsewhere and on Untagged.
    private(set) var shownTag: Tag?
    /// The lists of the tag page or Untagged, while one shows.
    private(set) var tagPage: TagBrowser?

    /// Calendar events and Reminders, shown before each day's tasks in the Agenda.
    let integrations: IntegrationsStore
    var todayEvents: [DayEvent] { integrations.todayEvents }
    var todayReminders: [ExternalReminder] { integrations.todayReminders }
    var upcomingEvents: [LocalDate: [DayEvent]] { integrations.upcomingEvents }
    var upcomingReminders: [LocalDate: [ExternalReminder]] { integrations.upcomingReminders }
    /// The events and reminders on any fetched day.
    /// A reminder's day is the one it's due on; today's are those due today or overdue.
    func events(on day: LocalDate) -> [DayEvent] {
        day == today ? todayEvents : upcomingEvents[day] ?? integrations.pastEvents[day] ?? []
    }
    func reminders(on day: LocalDate) -> [ExternalReminder] {
        day == today ? todayReminders : upcomingReminders[day] ?? integrations.pastReminders[day] ?? []
    }

    /// Whether any event covers `day`, for the month calendar's and week strip's dots.
    func hasEvents(on day: LocalDate) -> Bool {
        !events(on: day).isEmpty
    }

    /// Settings ▸ Notifications: the app icon's badge.
    let notifications: NotificationsStore
    var todayCount: Int { todayTasks.count { !$0.properties.status.isClosed } }
    var looseCount: Int { looseTasks.count }

    /// Changes the index, then the lists. Several changes in one call update the lists once.
    private func updateIndex(_ change: (inout VaultIndex) -> Void) {
        change(&index)
        boxLineCache = boxLineCache.filter { index[$0.key] == $0.value.item }
        updateLists()
    }

    /// Puts an edited item in the index. When its properties are unchanged, as when typing in its body, the lists keep
    /// their order and take the new item in place of the old; a change to its tags redoes only the tag lists.
    private func updateIndex(replacing item: Item) {
        guard let old = index[item.path], old.properties == item.properties else { return updateIndex { $0.update(item) } }
        index.update(item)
        if old.checkboxes != item.checkboxes, let date = dailyNoteNames.date(atPath: item.path), agendaMarksRange.contains(date) {
            updateAgendaMarks()
        }
        if let i = todayTasks.firstIndex(where: { $0.path == item.path }) { todayTasks[i] = item }
        if let i = looseTasks.firstIndex(where: { $0.path == item.path }) { looseTasks[i] = item }
        for i in upcoming.indices where upcoming[i].item.path == item.path { upcoming[i].item = item }
        if let i = agendaTasks.firstIndex(where: { $0.path == item.path }) { agendaTasks[i] = item }
        for i in agendaWeekEntries.indices where agendaWeekEntries[i].item.path == item.path { agendaWeekEntries[i].item = item }
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
            patch(&page.notes)
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
        updateNotes()
        updateAgenda()
        notifications.update(count: todayCount)
    }

    /// The selected period's tasks or entries, the dots for the days shown, and the events and reminders to fetch.
    private func updateAgenda() {
        switch agendaSelection {
        case let .day(day):
            agendaTasks = index.agendaDay(day, today: today)
            agendaWeekEntries = []
        case let .week(week):
            agendaTasks = []
            agendaWeekEntries = index.agendaWeek(week)
        }
        updateAgendaMarks()
        updateIntegrations()
    }

    private func updateAgendaMarks() {
        let range = agendaMarksRange
        agendaMarks = index.dayMarks(from: range.lowerBound, through: range.upperBound, names: dailyNoteNames)
    }

    /// The days the Agenda shows: the selected week, or when the month is open, every week of its month.
    var agendaRange: ClosedRange<LocalDate> {
        let week: ISOWeek
        switch agendaSelection {
        case let .day(day): week = day.isoWeek
        case let .week(selected): week = selected
        }
        let weeks = agendaAnchor.isoWeeksOfMonth
        guard agendaMonthOpen, let first = weeks.first, let last = weeks.last else {
            return week.firstDay...week.firstDay.adding(days: 6)
        }
        return first.firstDay...last.firstDay.adding(days: 6)
    }

    /// The days `agendaRange` shows and those of the page before and after it (a week, or a month), which a swipe draws.
    var agendaMarksRange: ClosedRange<LocalDate> {
        let range = agendaRange
        guard agendaMonthOpen else { return range.lowerBound.adding(days: -7)...range.upperBound.adding(days: 7) }
        let month = agendaAnchor.startOfMonth
        let first = month.addingMonths(-1).isoWeeksOfMonth.first?.firstDay ?? range.lowerBound
        let last = month.addingMonths(1).isoWeeksOfMonth.last?.firstDay.adding(days: 6) ?? range.upperBound
        return first...last
    }

    /// Steps the Agenda a day, or a week when a week is selected.
    func stepAgenda(by offset: Int) {
        switch agendaSelection {
        case let .day(day): agendaSelection = .day(day.adding(days: offset))
        case let .week(week): agendaSelection = .week(week.adding(weeks: offset))
        }
    }

    func showAgendaToday() {
        agendaSelection = .day(today)
    }

    /// Fetches events and reminders from the earlier of today and the first day shown to the later of Upcoming's last
    /// date, the end of next month, which the month calendar shows, and the last day shown, but no more than a year
    /// ahead of today.
    private func updateIntegrations() {
        let range = agendaRange
        integrations.update(today: today, from: range.lowerBound,
                            through: max(range.upperBound, Self.integrationsWindowEnd(today: today, upcomingLast: upcoming.last?.date)))
    }

    static func integrationsWindowEnd(today: LocalDate, upcomingLast: LocalDate?) -> LocalDate {
        min(max(upcomingLast ?? today, endOfNextMonth(after: today)), today.adding(days: 365))
    }

    static func endOfNextMonth(after day: LocalDate) -> LocalDate {
        let (year, month) = day.month >= 11 ? (day.year + 1, day.month - 10) : (day.year, day.month + 2)
        return LocalDate(year: year, month: month, day: 1)!.adding(days: -1)
    }

    /// Assigning a value equal to the old one would still redraw the Notes sidebar.
    private func updateNotes() {
        let tree = index.folderTree(folders: knownFolders), loose = index.looseNotes().count
        if tree != folderTree { folderTree = tree }
        if loose != looseNoteCount { looseNoteCount = loose }
    }

    /// Finds the folders on disk again. A folder page whose folder is gone shows Loose.
    private func rescanFolders(_ vault: Vault) async {
        let empty = await Self.run { vault.emptyFolders() }
        let known = empty.union(index.notes.map { Vault.folder(of: $0.path) }.filter { !$0.isEmpty })
        if known != knownFolders {
            knownFolders = known
            updateNotes()
        }
        if let folder = shownFolder, !folder.isEmpty, !(await Self.run { vault.folderExists(folder) }) { domain = .folder("") }
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
