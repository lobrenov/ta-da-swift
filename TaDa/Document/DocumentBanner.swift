// Over the document when its file changed outside Ta Da: what happened and the choices.
#if os(macOS)
import SwiftUI
import TaDaCore

struct DocumentBanner: View {
    let model: AppModel
    let document: OpenDocument
    @Environment(\.theme) private var theme

    var body: some View {
        if document.diskText != nil {
            banner("This file changed outside Ta Da while you were editing it. Nothing is saved until you choose.") {
                Button("Keep My Edits") { Task { await model.keepMine(document) } }
                Button("Use the File on Disk") { model.useTheirs(document) }
            }
        } else if document.isRemovedOnDisk {
            banner("This file was deleted or renamed outside Ta Da. Your unsaved edits are still here.") {
                Button("Save It Again") { Task { await model.saveAgain(document) } }
                Button("Discard My Edits") { model.discardRemoved(document) }
            }
        } else if let version = document.conflicts.first {
            let from = [version.device.map { "from \($0)" },
                        version.modified.map { "saved \($0.formatted(.relative(presentation: .named)))" }]
                .compactMap { $0 }.joined(separator: ", ")
            banner("iCloud kept another version of this file\(from.isEmpty ? "" : " (\(from))").") {
                Button("Keep This Version") { Task { await model.keepCurrentVersion(document) } }
                Button("Use the Other Version") { Task { await model.adopt(version, for: document) } }
            }
        }
    }

    private func banner(_ message: String, @ViewBuilder actions: () -> some View) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.color(\.blocked))
                    .accessibilityHidden(true)
                Text(message).foregroundStyle(theme.color(\.fg)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                actions().controlSize(.small)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(theme.color(\.surface))
            Hairline()
        }
        .accessibilityElement(children: .contain)
    }
}
#endif
