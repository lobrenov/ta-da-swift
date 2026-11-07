// A task in Live mode: title (rename by editing), properties, the body in the live editor, and a footer.
import SwiftUI
import TaDaCore

#if os(macOS)
struct LiveDocumentView: View {
    let model: AppModel
    let document: OpenDocument
    @State private var toc = TocState()
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TitleField(model: model, document: document, size: 23)
                    if let item = document.item {
                        PropertyChips(model: model, item: item)
                    }
                    WarningList(warnings: warnings)
                    Hairline()
                    BodyEditor(model: model, document: document, toc: toc)
                    Spacer(minLength: 0)
                    DocumentFooter(document: document)
                }
                .padding(.horizontal, 44)
                .padding(.top, 30)
                .padding(.bottom, 40)
                .frame(minHeight: viewport.size.height, alignment: .top)
            }
        }
        .tocPanel(model: model, document: document, state: toc)
    }

    private var warnings: [Warning] {
        guard let item = document.item else { return [] }
        return model.index[item.path].map { model.index.warnings(for: $0) } ?? item.warnings
    }
}

#endif

/// The body in the live editor, growing with its text so the page scrolls as one.
struct BodyEditor: View {
    let model: AppModel
    let document: OpenDocument
    /// Opens a link's file; by default the model follows it (`AppModel.openLink(to:)`).
    var open: ((String) -> Void)? = nil
    /// Opens a clicked tag; by default the model shows its page.
    var openTag: ((Tag) -> Void)? = nil
    /// Gets the page's visible lines and a way to scroll a line to the top.
    var toc: TocState? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        LiveEditor(
            text: Binding { document.body } set: { newValue in
                document.body = newValue
                #if os(macOS)
                toc?.typing = true
                #endif
            },
            theme: theme,
            documentID: document.path,
            linkTargets: model.index.titles,
            linkStatuses: model.taskLinkBoxes ? model.index.taskStatuses : [:],
            fitsContent: true,
            autocomplete: model.autocomplete,
            haptics: model.haptics,
            links: LinkMenuSource(index: model.index, vault: model.vault, attachments: model.attachments, recent: model.recentFiles, openPath: document.path),
            embedImage: model.embed,
            imageActions: model,
            taskExtraction: model,
            takesFocus: model.bodyFocus == document.path,
            onTookFocus: { model.bodyFocus = nil },
            onLinkClick: openLink,
            onTagClick: { name in
                guard let tag = Tag(name) else { return }
                if let openTag { openTag(tag) } else { model.show(.tag(tag.path)) }
            },
            onVisibleLines: visibleLinesReport,
            scroll: scroll
        )
        // The editor insets its text by 16pt; line it up with the title.
        .padding(.horizontal, -16)
        .accessibilityLabel("Body")
    }

    private var visibleLinesReport: ((ClosedRange<Int>) -> Void)? {
        toc.map { toc in { toc.visibleLines = $0 } }
    }

    private var scroll: EditorScroll? {
        toc?.scroll
    }

    private func openLink(_ target: String) {
        guard let link = WikiLink(inner: target), let item = model.index.items(titled: link.title).first else { return }
        if let open { open(item.path) } else { model.openLink(to: item.path) }
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
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme

    private var title: String { Item.title(ofPath: document.path) }

    var body: some View {
        TextField("Title", text: $draft, selection: $selection, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: size, weight: .bold))
            .tracking(-size / 100)
            .foregroundStyle(theme.color(\.strong))
            .focused($focused)
            .onSubmit { focused = false }
            #if os(macOS)
            .onExitCommand {
                draft = title
                focused = false
            }
            #endif
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

    /// A file just created asks for its title to take focus, selected, ready to type a name.
    private func takeFocusIfAsked() {
        guard model.titleFocus == document.path else { return }
        model.titleFocus = nil
        selection = TextSelection(range: draft.startIndex..<draft.endIndex)
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

/// When the file was last modified. Its created date and backlinks are in the properties' meta line.
struct DocumentFooter: View {
    let document: OpenDocument
    @Environment(\.theme) private var theme

    var body: some View {
        if let modified = document.modified {
            TimelineView(.everyMinute) { _ in
                Text("Modified \(modified.formatted(.relative(presentation: .named)))")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(theme.color(\.muted))
        }
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
                            .accessibilityHidden(true)
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
        case let .invalidRepeat(value):
            "`repeat` isn’t a rule like “every week on Mon”: “\(value)”, so the task doesn’t repeat."
        case let .invalidProject(value):
            "`project` isn’t a link like \"[[Project]]\": “\(value)”."
        case let .unexpectedValue(key):
            "`\(key)` has a list or mapping where Ta Da expects text, or the other way round."
        case let .unresolvedProject(title):
            "No project is called “\(title)”, so this is a loose task."
        case let .unresolvedArea(title):
            "No area is called “\(title)”, so this file has no parent."
        case let .areaIgnored(title):
            "The `area` “\(title)” is ignored: a task names its project or its area, and this one has a `project`."
        }
    }
}
