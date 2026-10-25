// The Other tab: Logbook, Attachments and Trash, and Settings (Vault, Themes, Editor, Daily notes, Integrations, Notifications, Haptics), with the folder's sync state under them.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneOtherScreen: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        List {
            Section {
                NavigationLink(value: PhoneRoute.logbook) {
                    row("Logbook", AppModel.Domain.logbook.systemImage, tint: \.done, value: "")
                }
                NavigationLink(value: PhoneRoute.attachments) {
                    row("Attachments", AppModel.Domain.attachments.systemImage, tint: \.link,
                        value: Attachment.sizeText(model.attachmentGroups.totalSize))
                }
                NavigationLink(value: PhoneRoute.trash) {
                    row("Trash", "trash", tint: \.muted, value: "\(model.trashCount)")
                }
            }
            Section {
                NavigationLink(value: PhoneRoute.settings(.vault)) {
                    row("Vault", "folder", tint: \.accent, value: model.vault?.root.lastPathComponent ?? "")
                }
                NavigationLink(value: PhoneRoute.settings(.themes)) {
                    row("Themes", "paintpalette", tint: \.link, value: model.usesSchemePerAppearance ? "Custom" : model.themeSet.name)
                }
                NavigationLink(value: PhoneRoute.settings(.editor)) {
                    row("Editor", "pencil", tint: \.doing, value: "")
                }
                NavigationLink(value: PhoneRoute.settings(.dailyNotes)) {
                    row("Daily notes", "calendar.badge.clock", tint: \.done, value: "")
                }
                NavigationLink(value: PhoneRoute.integrations) {
                    row("Integrations", "calendar", tint: \.deadline, value: integrationsValue)
                }
                NavigationLink(value: PhoneRoute.settings(.notifications)) {
                    row("Notifications", "app.badge", tint: \.blocked, value: model.notifications.showsBadge ? "Badges" : "Off")
                }
                NavigationLink(value: PhoneRoute.settings(.haptics)) {
                    row("Haptics", "hand.tap", tint: \.due, value: model.haptics ? "On" : "Off")
                }
            } header: {
                Text("Settings")
            } footer: {
                SyncLine(model: model)
            }
            .listRowBackground(theme.color(\.code))
        }
        .listRowBackground(theme.color(\.code))
        .scrollContentBackground(.hidden)
        .background(theme.color(\.bg))
        .navigationTitle("Other")
    }

    /// "Events and reminders", "Events", "Reminders" or "Off".
    private var integrationsValue: String {
        switch (model.integrations.isShown(.events), model.integrations.isShown(.reminders)) {
        case (true, true): "Events and reminders"
        case (true, false): "Events"
        case (false, true): "Reminders"
        case (false, false): "Off"
        }
    }

    private func row(_ title: String, _ symbol: String, tint: KeyPath<Theme, PlatformColor>, value: String) -> some View {
        HStack {
            Label {
                Text(title).foregroundStyle(theme.color(\.fg))
            } icon: {
                Image(systemName: symbol).foregroundStyle(theme.color(tint))
            }
            Spacer()
            Text(value).foregroundStyle(theme.color(\.muted))
        }
    }
}

/// "Watching · iCloud Drive › Ta Da": whether changes are picked up as they happen, and where the folder is.
private struct SyncLine: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        Label {
            Text("\(model.isWatching ? "Watching" : "Checks when you open Ta Da") · \(model.folderDisplayName.replacing("/", with: " › "))")
        } icon: {
            Image(systemName: model.isInICloud ? "icloud" : "folder")
                .foregroundStyle(theme.color(model.isWatching ? \.done : \.blocked))
        }
        .scaledFont(size: 13)
        .foregroundStyle(theme.color(\.muted))
    }
}

// MARK: Settings

struct PhoneSettingsScreen: View {
    @Bindable var model: AppModel
    let section: SettingsSection
    @State private var isPicking = false
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section("Vault") {
                    value("Folder", model.folderDisplayName, monospaced: true)
                    LabeledContent("Sync") { SyncState(model: model) }
                    value("Contents", "\(tasks(model.index.tasks.count)) · \(model.index.projects.count) projects · \(model.index.areas.count) areas")
                    Button("Change Folder…") { isPicking = true }
                        .foregroundStyle(theme.color(\.accent))
                }
                .id(SettingsSection.vault)
                Section("Themes") {
                    ThemeSwatches(model: model)
                    Picker("Theme set", selection: Binding { model.themeSet } set: { model.choose($0) }) {
                        ForEach(ThemeSet.all) { Text($0.name).tag($0) }
                    }
                    Picker("Appearance", selection: $model.appearance) {
                        ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .id(SettingsSection.themes)
                Section("Editor Autocomplete") {
                    toggle("Brackets", "( [ {", \.brackets)
                    toggle("Text formatting", "** _ ==", \.formatting)
                    toggle("Wikilinks", "[[ ![[", \.wikiLinks)
                    toggle("Tags", "#", \.tags)
                }
                .id(SettingsSection.editor)
                dailyNotes
                    .id(SettingsSection.dailyNotes)
                notifications
                    .id(SettingsSection.notifications)
                Section {
                    Toggle("Haptics", isOn: $model.haptics)
                } header: {
                    Text("Haptics")
                } footer: {
                    Text("A tap you can feel when you complete a task, pick rows, or set a date or project.")
                }
                .id(SettingsSection.haptics)
            }
            .listRowBackground(theme.color(\.code))
            .scrollContentBackground(.hidden)
            .background(theme.color(\.bg))
            .tint(theme.color(\.accent))
            .navigationTitle("Settings")
            .folderImporter(isPresented: $isPicking, model: model)
            .onAppear { proxy.scrollTo(section, anchor: .top) }
        }
    }

    private var dailyNotes: some View {
        Group {
            Section {
                folderField($model.dailyFolder)
                template($model.dailyTemplate)
            } header: {
                Text("Daily notes")
            } footer: {
                Text("File name YYYY-MM-DD, e.g. \(model.dailyNoteExample)")
            }
            Section {
                Toggle("Week notes", isOn: $model.weekNotes)
                folderField($model.weekFolder)
                    .disabled(!model.weekNotes)
                template($model.weekTemplate)
                    .disabled(!model.weekNotes)
            } header: {
                Text("Week notes")
            } footer: {
                Text("File name GGGG-[W]WW, e.g. \(model.weekNoteExample).")
            }
        }
    }

    private func folderField(_ folder: Binding<String>) -> some View {
        LabeledContent("Folder") {
            DailyFolderField(folder: folder)
        }
    }

    private func template(_ template: Binding<String?>) -> some View {
        Picker("Template", selection: template) {
            Text("None").tag(String?.none)
            if let missing = model.missingTemplate(template.wrappedValue) {
                Text(missing.missingTemplateLabel).foregroundStyle(theme.color(\.muted)).tag(String?.some(missing))
            }
            ForEach(model.templateChoices) { Text($0.path.dropLast(3)).tag(String?.some($0.path)) }
        }
        .pickerStyle(.navigationLink)
    }

    private var notifications: some View {
        let store = model.notifications
        return Section {
            Toggle("Badges", isOn: Binding(get: { [.on, .asking].contains(store.access) },
                                           set: { on in Task { await store.setOn(on) } }))
                .disabled(store.access == .asking || store.access == .denied)
            if store.access == .denied {
                Button("Open Notification Settings") { openURL(NotificationsStore.settingsURL) }
                    .foregroundStyle(theme.color(\.accent))
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(store.access == .denied
                 ? "Ta Da can’t show badges. Turn on Allow Notifications and Badges in Settings ▸ Apps ▸ Ta Da ▸ Notifications."
                 : "Open tasks due or at their deadline today or earlier.")
        }
    }

    private func value(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(monospaced ? .system(size: 15, design: .monospaced) : nil)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func toggle(_ title: String, _ hint: String, _ key: WritableKeyPath<Autocomplete, Bool>) -> some View {
        Toggle(isOn: Binding { model.autocomplete[keyPath: key] } set: { model.autocomplete[keyPath: key] = $0 }) {
            HStack {
                Text(title)
                Spacer()
                Text(hint)
                    .scaledFont(size: 13, design: .monospaced)
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.color(\.surface), in: .rect(cornerRadius: 5))
            }
        }
    }
}

/// A folder path typed into a field, committed on Return or when the field loses focus; empty is the vault's top level.
private struct DailyFolderField: View {
    @Binding var folder: String
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Vault folder", text: $draft)
            .multilineTextAlignment(.trailing)
            .scaledFont(size: 15, design: .monospaced)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isFocused)
            .onSubmit(commit)
            .onAppear { draft = folder }
            .onChange(of: folder) { draft = folder }
            .onChange(of: isFocused) { if !isFocused { commit() } }
    }

    private func commit() {
        let cleaned = AppModel.cleanedFolder(draft)
        draft = cleaned
        if cleaned != folder { folder = cleaned }
    }
}

/// Watching (in `done`) or Not watching (in `blocked`), with iCloud's cloud when the folder is in iCloud Drive.
private struct SyncState: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: model.isInICloud ? "icloud" : "folder")
                .foregroundStyle(theme.color(model.isWatching ? \.done : \.blocked))
            Text(model.isWatching ? "Watching" : "Not watching")
        }
    }
}

/// One swatch per theme set: its background with its accent inside; the current set is ringed.
private struct ThemeSwatches: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ThemeSet.all) { set in
                let scheme = model.isDark ? set.dark : set.light
                let isCurrent = !model.usesSchemePerAppearance && set == model.themeSet
                Button { model.choose(set) } label: {
                    Circle()
                        .fill(scheme.color(\.bg))
                        .overlay(Circle().fill(scheme.color(\.accent)).padding(9))
                        .overlay(Circle().strokeBorder(scheme.color(\.border)))
                        .frame(width: 32, height: 32)
                        .padding(3)
                        .overlay { if isCurrent { Circle().strokeBorder(theme.color(\.accent), lineWidth: 2) } }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(set.name)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: Trash

struct PhoneTrashScreen: View {
    let model: AppModel
    @State private var picked: Set<String> = []
    @State private var isConfirmingEmpty = false
    @State private var search = ListSearch()
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        List {
            if search.isSearching {
                PhoneSearchResults(model: model, query: search.query)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                trashRows
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .pullToSearch(search)
        .background { theme.color(\.bg).ignoresSafeArea() }
        .overlay {
            if isEmpty, !search.isSearching {
                ContentUnavailableView("Trash is empty", systemImage: "trash")
            }
        }
        // While search is open its field takes the navigation bar's row.
        .navigationTitle(search.isOpen ? "" : "Trash")
        .navigationSubtitle(search.isOpen ? "" : "\(count) file\(count == 1 ? "" : "s") in .trash/\(picked.isEmpty ? "" : " · \(picked.count) selected")")
        .navigationBarBackButtonHidden(search.isOpen)
        .background { TabBarHiddenOnTop() }
        .toolbar {
            if search.isOpen {
                // Keeps the navigation bar, so the rows stay below the search field in its row.
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            } else {
                actions
            }
        }
        .onChange(of: model.trash) { picked.formIntersection(model.trash.map(\.id) + model.trashedAttachments.map(\.id)) }
        .onChange(of: model.trashedAttachments) { picked.formIntersection(model.trash.map(\.id) + model.trashedAttachments.map(\.id)) }
    }

    @ViewBuilder private var trashRows: some View {
        if let note = model.trashNote {
            Text(note).scaledFont(size: 13).foregroundStyle(theme.color(\.done))
                .listRowBackground(Color.clear)
        }
        let byFile = model.trashedAttachmentsByFile
        ForEach(model.trash) { trashed in
            row(trashed)
            ForEach(byFile[trashed.id] ?? []) { imageRow($0, wentWith: trashed) }
        }
        ForEach(model.looseTrashedAttachments) { trashed in
            imageRow(trashed)
        }
    }

    @ToolbarContentBuilder private var actions: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Restore \(picked.count == 1 ? "1 Item" : "\(picked.count) Items")") {
                let paths = picked
                picked = []
                Task { await model.restore(paths) }
            }
            .disabled(picked.isEmpty)
            Spacer()
            Button("Empty Trash", role: .destructive) { isConfirmingEmpty = true }
                .buttonStyle(.glassProminent)
                .tint(theme.color(\.deadline))
                .disabled(isEmpty)
                .confirmationDialog("Empty the trash?", isPresented: $isConfirmingEmpty, titleVisibility: .visible) {
                    Button("Empty Trash", role: .destructive) {
                        nav.play(.emptyTrash)
                        picked = []
                        Task { await model.emptyTrash() }
                    }
                } message: {
                    Text(count == 1
                         ? "The file goes to iCloud Drive’s Recently Deleted, or is deleted."
                         : "The \(count) files go to iCloud Drive’s Recently Deleted, or are deleted.")
                }
        }
    }

    private var count: Int { model.trashCount }
    private var isEmpty: Bool { count == 0 }

    /// An image deleted on its own, or (`wentWith`) one that went with a trashed file: it sits under the file, picked
    /// with it.
    private func imageRow(_ trashed: TrashedAttachment, wentWith file: TrashedItem? = nil) -> some View {
        let isPicked = picked.contains(trashed.id) || file.map { picked.contains($0.id) } == true
        return Button {
            if isPicked { picked.remove(trashed.id) } else { picked.insert(trashed.id) }
            nav.play(.pick)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .scaledFont(size: 22)
                    .foregroundStyle(isPicked ? theme.color(\.accent) : theme.color(\.border))
                ImageThumbnail(url: model.vault?.url(for: trashed.path), side: 18, cornerRadius: 4)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(trashed.name).scaledFont(size: 17).foregroundStyle(theme.color(\.fg))
                    Text(file.map { "Went with \($0.item.title)" }
                         ?? [model.embeddersSummary(of: trashed) ?? "Image",
                             trashed.deleted.map { "Deleted \(LocalDate($0).formatted(.weekdayDayMonth))" }]
                            .compactMap { $0 }.joined(separator: " · "))
                        .scaledFont(size: 13).foregroundStyle(theme.color(\.muted))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.leading, file == nil ? 0 : 28)
        .listRowBackground(isPicked ? theme.color(\.accent).opacity(theme.isDark ? 0.16 : 0.1) : Color.clear)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func row(_ trashed: TrashedItem) -> some View {
        let isPicked = picked.contains(trashed.id)
        let item = trashed.item
        return Button {
            if isPicked { picked.remove(trashed.id) } else { picked.insert(trashed.id) }
            nav.play(.pick)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .scaledFont(size: 22)
                    .foregroundStyle(isPicked ? theme.color(\.accent) : theme.color(\.border))
                if item.properties.kind == .area {
                    AreaIcon(size: 18).padding(.top, 2)
                } else {
                    Image(systemName: item.properties.kind == .project ? "chart.pie" : "doc.text")
                        .foregroundStyle(theme.color(\.muted))
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).scaledFont(size: 17).foregroundStyle(theme.color(\.fg))
                    Text(summary(trashed)).scaledFont(size: 13).foregroundStyle(theme.color(\.muted))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(isPicked ? theme.color(\.accent).opacity(theme.isDark ? 0.16 : 0.1) : Color.clear)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func summary(_ trashed: TrashedItem) -> String {
        let item = trashed.item
        var parts: [String] = []
        switch item.properties.kind {
        case .area:
            let contents = TrashedItem.contents(of: item, in: model.trash)
            parts.append("Area · deleted with \(contents.projects.count) project\(contents.projects.count == 1 ? "" : "s") and \(tasks(contents.tasks.count))")
        case .project:
            let linked = TrashedItem.tasks(of: item, in: model.trash).count
            parts.append("Project · \(linked) linked task\(linked == 1 ? "" : "s")" + (item.properties.area.map { " · \($0.title)" } ?? ""))
        case .task:
            parts.append(item.properties.project?.title ?? item.properties.area?.title ?? "Loose task")
        case .note:
            parts.append("Note")
        }
        if let deleted = trashed.deleted {
            parts.append("Deleted \(LocalDate(deleted).formatted(.weekdayDayMonth))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: Onboarding

/// First run, or the saved folder is gone: what Ta Da does with a folder, and Choose Folder.
struct PhoneOnboardingView: View {
    let model: AppModel
    @State private var isPicking = false
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(theme.color(\.accent), in: .rect(cornerRadius: 22))
                    .padding(.top, 60)
                    .accessibilityHidden(true)
                VStack(spacing: 12) {
                    Text("Ta Da").scaledFont(size: 34, weight: .bold).dynamicTypeSize(...DynamicTypeSize.xxxLarge).foregroundStyle(theme.color(\.strong))
                    Text("Every task and project is a markdown file in a folder you choose.")
                        .scaledFont(size: 17)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.color(\.fg))
                }
                VStack(alignment: .leading, spacing: 20) {
                    feature("folder", \.accent, "Your folder, your files",
                            "Pick a folder on iCloud Drive. One inside your Obsidian vault works too.")
                    feature("doc.text", \.link, "Plain markdown",
                            "Frontmatter holds status and dates. Ta Da edits only the lines it changes.")
                    feature("icloud", \.done, "Same tasks on your Mac",
                            "iCloud Drive keeps the folder in step with Ta Da on macOS.")
                }
                if case let .failed(message) = model.state {
                    Text(message)
                        .scaledFont(size: 15)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.color(\.deadline))
                }
            }
            .padding(.horizontal, 32)
        }
        .safeAreaInset(edge: .bottom) {
            Button { isPicking = true } label: {
                Text("Choose Folder…").scaledFont(size: 17, weight: .semibold).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(theme.color(\.accent))
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(theme.color(\.bg))
        .folderImporter(isPresented: $isPicking, model: model)
    }

    private func feature(_ symbol: String, _ tint: KeyPath<Theme, PlatformColor>, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(theme.color(tint))
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).scaledFont(size: 17, weight: .semibold).foregroundStyle(theme.color(\.strong))
                Text(text).scaledFont(size: 15).foregroundStyle(theme.color(\.muted))
            }
        }
    }
}
#endif
