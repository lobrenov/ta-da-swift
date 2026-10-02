// A task in Live mode: title (rename by editing), properties, the body in the live editor, and a footer.
import SwiftUI
import TaDaCore

struct LiveDocumentView: View {
    let model: AppModel
    let document: OpenDocument
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TitleField(model: model, document: document, size: 23)
                    if let item = document.item {
                        PropertyTable(model: model, item: item, keys: PropertyTable.taskKeys)
                    }
                    WarningList(warnings: warnings)
                    Hairline()
                    BodyEditor(model: model, document: document)
                    Spacer(minLength: 0)
                    DocumentFooter(model: model, document: document)
                }
                .padding(.horizontal, 44)
                .padding(.top, 30)
                .padding(.bottom, 40)
                .frame(minHeight: viewport.size.height, alignment: .top)
            }
        }
    }

    private var warnings: [Warning] {
        guard let item = document.item else { return [] }
        return model.index[item.path].map { model.index.warnings(for: $0) } ?? item.warnings
    }
}

/// The body in the live editor, growing with its text so the page scrolls as one.
struct BodyEditor: View {
    let model: AppModel
    let document: OpenDocument
    @Environment(\.theme) private var theme

    var body: some View {
        LiveEditor(
            text: Binding { document.body } set: { document.body = $0 },
            theme: theme,
            documentID: document.path,
            linkTargets: Set(model.index.items.values.map { $0.title.lowercased() }),
            fitsContent: true,
            onLinkClick: openLink
        )
        // The editor insets its text by 16pt; line it up with the title.
        .padding(.horizontal, -16)
    }

    private func openLink(_ target: String) {
        guard let link = WikiLink(inner: target), let item = model.index.items(titled: link.title).first else { return }
        model.open(item.path)
    }
}

/// The file's title. Editing it renames the file when you press Return or click away; Escape reverts.
struct TitleField: View {
    let model: AppModel
    let document: OpenDocument
    let size: CGFloat
    @State private var draft = ""
    /// The file whose title is being edited. The view is reused across files, so a commit only renames
    /// the file the editing started in, and only while it's still the one shown.
    @State private var editingPath: String?
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme

    private var title: String { Item.title(ofPath: document.path) }

    var body: some View {
        TextField("Title", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: size, weight: .bold))
            .tracking(-size / 100)
            .foregroundStyle(theme.color(\.strong))
            .focused($focused)
            .onSubmit { focused = false }
            .onExitCommand {
                draft = title
                focused = false
            }
            .onChange(of: draft) {
                // Return ends editing; a title is one line.
                guard draft.contains(where: \.isNewline) else { return }
                draft = draft.filter { !$0.isNewline }
                focused = false
            }
            .onChange(of: focused) {
                if focused { editingPath = document.path } else { commit() }
            }
            .onChange(of: document.path, initial: true) {
                draft = title
                if editingPath != document.path { editingPath = nil }
                takeFocusIfAsked()
            }
            .onChange(of: model.titleFocus) { takeFocusIfAsked() }
            .accessibilityLabel("Title")
            .help("Rename the file")
    }

    /// A file just created asks for its title to take focus, ready to type a name.
    private func takeFocusIfAsked() {
        guard model.titleFocus == document.path else { return }
        model.titleFocus = nil
        focused = true
    }

    private func commit() {
        defer { editingPath = nil }
        let new = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path = editingPath, path == document.path, !new.isEmpty, new != title else {
            draft = title
            return
        }
        Task {
            await model.rename(path, to: new)
            draft = title
        }
    }
}

/// Created and modified dates, and the files that link here.
struct DocumentFooter: View {
    let model: AppModel
    let document: OpenDocument
    @Environment(\.theme) private var theme

    var body: some View {
        let backlinks = document.item.map { model.index.backlinks(to: $0) } ?? []
        HStack(spacing: 16) {
            if let created = document.item?.properties.createdDate {
                Text("Created \(created.description)")
            }
            if let modified = document.modified {
                TimelineView(.everyMinute) { _ in
                    Text("Modified \(modified.formatted(.relative(presentation: .named)))")
                }
            }
            if backlinks.isEmpty {
                Text("0 backlinks")
            } else {
                Menu("\(backlinks.count) backlink\(backlinks.count == 1 ? "" : "s")") {
                    ForEach(backlinks) { item in
                        Button(item.title) { model.open(item.path) }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(theme.color(\.muted))
    }
}

/// Problems Ta Da found reading the file. The file still loads.
struct WarningList: View {
    let warnings: [Warning]
    @Environment(\.theme) private var theme

    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(warnings, id: \.self) { warning in
                    Label {
                        Text(warning.message)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.color(\.blocked))
                    }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(theme.color(\.fg))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Warnings")
        }
    }
}

extension Warning {
    var message: LocalizedStringKey {
        switch self {
        case let .invalidYAML(problem, line):
            "The frontmatter isn’t valid YAML\(line.map { " (line \($0))" } ?? ""): \(problem). Only `type` was read."
        case .missingStatus:
            "No `status`, so it reads as Not Started."
        case let .unknownStatus(value):
            "Unknown status “\(value)”, so it reads as Not Started."
        case let .invalidDate(key, value):
            "`\(key)` isn’t a YYYY-MM-DD date: “\(value)”."
        case let .invalidProject(value):
            "`project` isn’t a link like \"[[Project]]\": “\(value)”."
        case let .unexpectedValue(key):
            "`\(key)` has a list or mapping where Ta Da expects text, or the other way round."
        case let .unresolvedProject(title):
            "No project is called “\(title)”, so this is a loose task."
        }
    }
}
