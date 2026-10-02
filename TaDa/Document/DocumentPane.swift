// The document column: a breadcrumb bar over the selected file, or a prompt when nothing is selected.
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
                if let item = document.item, item.properties.kind == .project {
                    ProjectDocumentView(model: model, document: document, project: model.index[item.path] ?? item)
                } else {
                    LiveDocumentView(model: model, document: document)
                }
            }
        } else if let error = model.documentError, model.selection != nil {
            EmptyState(systemImage: "exclamationmark.triangle", title: "Couldn’t open the file", message: "\(error)")
        } else if model.selection == nil {
            EmptyState(systemImage: "doc.text", title: "No task selected", message: "Pick a task to read and edit it here.")
        } else {
            Color.clear
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
            Spacer(minLength: 12)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(theme.color(\.muted))
        .lineLimit(1)
        .padding(.horizontal, 20)
        .frame(height: 46)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(document.path)
    }
}
