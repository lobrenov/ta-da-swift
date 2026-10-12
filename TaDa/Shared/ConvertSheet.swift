// Converting a note to a task, project or area: a window sheet for `model.convertRequest` (ContentView shows it) with a
// Task | Project | Area switch, status and parent menus (not for an area), where the file moves, the frontmatter lines
// added, and what happens to its checkboxes and links. Convert writes it and opens the file in Tasks.
import SwiftUI
import TaDaCore

/// What converting a note will do, worked out from its text.
struct ConvertPreview: Equatable {
    struct Line: Hashable {
        enum Change { case kept, added, removed }
        let change: Change
        let text: String
    }

    /// The note's path, and the path it moves to.
    let from: String
    let to: String
    /// The frontmatter block after converting, its added lines marked, then before its closing `---` the lines converting
    /// replaces or removes.
    let lines: [Line]
    /// What happens to the checkboxes.
    let subtasks: String
    /// What happens to the links to it.
    let links: String

    /// `text` is the note's text as it will be converted (the open document's, unsaved edits included); `taken` holds the
    /// filenames the name is numbered against (the folder's, and for a project every project's); `folderLinks` counts the
    /// links written with the note's path.
    init(note: Item, text: String, kind: Item.Kind, status: Status, parent: Parent?, today: LocalDate,
         taken: Set<String>, folderLinks: Int) {
        let folder = kind == .area ? Vault.areaFolder : kind == .project ? Vault.projectFolder : Vault.taskFolder
        from = note.path
        to = folder + "/" + Vault.movedName(of: note.path, existing: taken)
        let converted = NoteConversion.text(text, to: kind, status: status, parent: parent, today: today)
        func lines(_ text: String) -> [String] {
            FrontmatterSplitter.split(text).block.split(whereSeparator: \.isNewline).map(String.init)
        }
        var old = lines(text)
        var new = lines(converted).map { line in
            if let i = old.firstIndex(of: line) {
                old.remove(at: i)
                return Line(change: .kept, text: line)
            }
            return Line(change: .added, text: line)
        }
        new.insert(contentsOf: old.map { Line(change: .removed, text: $0) }, at: max(new.count - 1, 0))
        self.lines = new
        let parsed = Item(parsing: text, path: note.path) ?? note
        let boxes = parsed.checkboxes.count { $0.state != .icon }, (done, total) = parsed.subtasks
        subtasks = switch kind {
        case _ where boxes == 0: "It has no checkboxes."
        case .area: "An area counts no subtasks; its checkboxes stay as written."
        case .task: "\(boxes == 1 ? "1 checkbox becomes its subtask" : "\(boxes) checkboxes become its subtasks") · \(done)/\(total)"
        default: "\(boxes == 1 ? "1 checkbox stays" : "\(boxes) checkboxes stay") the project file’s own subtasks · \(done)/\(total)"
        }
        links = folderLinks == 0 ? "Links to it by title keep working."
            : "\(folderLinks == 1 ? "1 link" : "\(folderLinks) links") written with its folder \(folderLinks == 1 ? "is" : "are") rewritten."
    }
}

#if os(macOS)
struct ConvertSheet: View {
    let model: AppModel
    let request: AppModel.ConvertRequest
    @State private var kind = Item.Kind.task
    @State private var status = Status.notStarted
    @State private var parent: Parent?
    @State private var text: String?
    @State private var taken: [Item.Kind: Set<String>]?
    @Environment(\.theme) private var theme

    private var note: Item? { model.index[request.path] }

    private var kindName: String {
        switch kind {
        case .task: "Task"
        case .project: "Project"
        default: "Area"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Convert “\(Item.title(ofPath: request.path))” to \(kind == .area ? "an area" : "a \(kindName.lowercased())")")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.color(\.strong))
            typeSwitch
            if kind != .area {
                HStack(spacing: 6) {
                    statusMenu
                    parentMenu
                }
            }
            if let note, let text, let taken {
                let preview = ConvertPreview(note: note, text: text, kind: kind, status: status, parent: parent, today: model.today,
                                             taken: taken[kind] ?? [], folderLinks: folderLinks(to: note))
                details(preview)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { model.convertRequest = nil }
                    .buttonStyle(ActionButtonStyle(height: 28))
                    .keyboardShortcut(.cancelAction)
                Button("Convert to \(kindName)") { convert() }
                    .buttonStyle(ActionButtonStyle(kind: .primary, height: 28))
                    .keyboardShortcut(.defaultAction)
                    .disabled(note == nil || text == nil || taken == nil)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(theme.color(\.fg))
        .padding(20)
        .frame(width: 480)
        .onAppear { kind = request.kind }
        .onChange(of: kind) {
            if kind == .project, case .project = parent { parent = nil }
            if !Status.choices(for: kind).contains(status) { status = .notStarted }
        }
        .task { await load() }
    }

    private var typeSwitch: some View {
        HStack(spacing: 2) {
            ForEach([Item.Kind.task, .project, .area], id: \.self) { value in
                let selected = kind == value
                Button { kind = value } label: {
                    HStack(spacing: 6) {
                        switch value {
                        case .task:
                            RoundedRectangle(cornerRadius: 3).strokeBorder(theme.color(\.muted), lineWidth: 1.3).frame(width: 11, height: 11)
                            Text("Task")
                        case .project:
                            ProgressRing(fraction: 0).foregroundStyle(theme.color(\.accent)).scaleEffect(12 / 14).frame(width: 12, height: 12)
                            Text("Project")
                        default:
                            AreaIcon(size: 12)
                            Text("Area")
                        }
                    }
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(theme.color(selected ? \.strong : \.fg))
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(selected ? theme.color(\.bg) : .clear, in: .rect(cornerRadius: 6))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(theme.color(\.surface), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Type")
    }

    private var statusMenu: some View {
        Menu {
            ForEach(Status.choices(for: kind), id: \.self) { value in
                Button(value.rawValue) { status = value }
            }
        } label: {
            chip(status.rawValue, systemImage: nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Status, \(status.rawValue)")
    }

    private var parentMenu: some View {
        Menu {
            Button("None") { parent = nil }
            if kind == .task, !model.projects.isEmpty {
                Section("Projects") {
                    ForEach(model.projects) { progress in
                        Button(progress.project.title) { parent = .project(progress.project.title) }
                    }
                }
            }
            if !model.areas.isEmpty {
                Section("Areas") {
                    ForEach(model.areas) { area in
                        Button(area.area.title) { parent = .area(area.area.title) }
                    }
                }
            }
        } label: {
            if let parent {
                chip(parent.title, systemImage: nil)
            } else {
                chip(kind == .task ? "Project or area" : "Area", systemImage: "plus", dashed: true)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(parent.map { "Filed under \($0.title)" } ?? "No parent")
    }

    private func chip(_ title: String, systemImage: String?, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(title)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(theme.color(dashed ? \.muted : \.strong))
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background(dashed ? .clear : theme.color(\.surface), in: .capsule)
        .overlay(Capsule().strokeBorder(theme.color(\.surface), style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : [])))
        .contentShape(.capsule)
    }

    private func details(_ preview: ConvertPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Moves") {
                HStack(spacing: 6) {
                    Text(preview.from).foregroundStyle(theme.color(\.muted))
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(theme.color(\.muted))
                    Text(preview.to).foregroundStyle(theme.color(\.strong))
                }
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            }
            section("Frontmatter") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(preview.lines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 8) {
                            Text(line.change == .added ? "+" : line.change == .removed ? "−" : " ")
                                .foregroundStyle(theme.color(line.change == .removed ? \.deadline : \.done)).frame(width: 8)
                            Text(line.text)
                                .strikethrough(line.change == .removed)
                                .foregroundStyle(theme.color(line.change == .added ? \.strong : \.muted))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(line.change == .added ? theme.color(\.done).opacity(0.14) : .clear)
                        .accessibilityLabel(line.change == .added ? "Added \(line.text)" : line.change == .removed ? "Removed \(line.text)" : line.text)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.vertical, 6)
                .background(theme.color(\.code), in: .rect(cornerRadius: 7))
                .accessibilityElement(children: .combine)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.subtasks)
                Text(preview.links)
            }
            .font(.system(size: 12))
            .foregroundStyle(theme.color(\.muted))
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(theme.color(\.muted))
            content()
        }
    }

    /// Links in other files written with the note's path.
    private func folderLinks(to note: Item) -> Int {
        let bare = String(note.path.dropLast(3)).lowercased()
        return model.index.items.values.reduce(0) { count, item in
            count + item.links.count { link in
                let target = link.target.lowercased()
                return target.contains("/") && (target == bare || target == bare + ".md")
            }
        }
    }

    /// The note's text (the open document's, if it's open) and the names each kind's folder has taken.
    private func load() async {
        guard let vault = model.vault else { return }
        let path = request.path, projects = model.index.projectFilenames()
        let open = model.document.flatMap { $0.path == path ? $0.text : nil }
        // Both at once, so the preview never shows a name before it's numbered.
        let (read, names) = await Task.detached { () -> (String?, [Item.Kind: Set<String>]) in
            (open ?? (try? vault.read(path)),
             [.task: vault.filenames(in: Vault.taskFolder), .project: vault.filenames(in: Vault.projectFolder).union(projects),
              .area: vault.filenames(in: Vault.areaFolder)])
        }.value
        text = read
        taken = names
    }

    private func convert() {
        let (path, kind, status, parent) = (request.path, kind, status, kind == .area ? nil : parent)
        model.convertRequest = nil
        Task { await model.convert(path, to: kind, status: status, parent: parent) }
    }
}
#endif
