// The document column: a breadcrumb bar over the selected file, or a prompt when nothing is selected.
#if os(macOS)
import SwiftUI
import TaDaCore

struct DocumentPane: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        if let document = model.document {
            VStack(spacing: 0) {
                DocumentBar(model: model, document: document)
                Hairline()
                DocumentBanner(model: model, document: document)
                if model.isSourceMode {
                    HStack(spacing: 0) {
                        SourceEditor(text: Binding { document.text } set: { document.text = $0 },
                                     theme: theme, documentID: document.path)
                            .frame(maxWidth: 760 + 2 * SourceTextView.gutter)
                            .frame(maxWidth: .infinity)
                        Hairline(axis: .vertical)
                        FileInspector(model: model, document: document)
                    }
                } else if let item = document.item, item.properties.kind == .project {
                    ProjectDocumentView(model: model, document: document, project: model.index[item.path] ?? item)
                } else {
                    LiveDocumentView(model: model, document: document)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let extracted = model.extracted {
                    ExtractedToast(model: model, extracted: extracted)
                        .padding(20)
                }
            }
        } else if let error = model.documentError, model.selection != nil {
            EmptyState(systemImage: "exclamationmark.triangle", title: "Couldn’t open the file", message: "\(error)")
        } else if model.selection == nil, model.multiSelection.count > 1 {
            EmptyState(systemImage: "doc.on.doc", title: "\(model.multiSelection.count) tasks selected")
        } else if model.selection == nil, model.domain == .agenda, !model.isSearching, let create = agendaCreation {
            EmptyState(systemImage: "doc.text", title: create.title, message: "Uses the template set in Settings ▸ Daily notes.",
                       button: ("Create \(create.file)", { Task { await model.openOrCreateNote(for: model.agendaSelection) } }))
        } else if model.selection == nil {
            EmptyState(systemImage: "doc.text", title: "No task selected")
        } else {
            Color.clear
        }
    }
}

extension DocumentPane {
    /// What the Agenda's empty pane offers: the note for its day, or for its week while week notes are on.
    private var agendaCreation: (title: String, file: String)? {
        let file = String(model.notePath(for: model.agendaSelection).split(separator: "/").last ?? "")
        switch model.agendaSelection {
        case .day: return ("No note for this day yet.", file)
        case .week: return model.weekNotes ? ("No note for this week yet.", file) : nil
        }
    }
}

/// "Ta Da / tasks / file.md": the folder, the file's folders and its name.
private struct DocumentBar: View {
    let model: AppModel
    let document: OpenDocument
    @Environment(\.theme) private var theme

    var body: some View {
        let parts = document.path.split(separator: "/").map(String.init)
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc").font(.system(size: 12))
                ForEach(Array(([model.vault?.root.lastPathComponent ?? ""] + parts.dropLast()).enumerated()), id: \.offset) { _, part in
                    Text(part)
                    Text("/")
                }
                Text(parts.last ?? "")
                    .foregroundStyle(theme.color(\.fg))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if document.isDirty {
                    Circle().fill(theme.color(\.muted)).frame(width: 6, height: 6)
                        .help("Unsaved changes")
                        .accessibilityLabel("Unsaved changes")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(document.path)
            Spacer(minLength: 12)
            SegmentedControl(label: "Editor mode", options: [(false, "Live"), (true, "Source")],
                             selection: Binding { model.isSourceMode } set: { model.isSourceMode = $0 }, shortcut: "⌘E")
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(theme.color(\.muted))
        .lineLimit(1)
        .padding(.horizontal, 20)
        .frame(height: 46)
    }
}
#endif
