// First run, or the saved folder is gone: pick the folder that holds the task and project files.
import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerView: View {
    let model: AppModel
    @Environment(\.theme) private var theme
    @State private var isPicking = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.color(\.accent))
                .accessibilityHidden(true)
            Text("Ta Da")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(theme.color(\.strong))
            Text("Choose the folder that holds your tasks and projects. Ta Da reads the markdown files whose frontmatter says `type: task` or `type: project`, and leaves every other file alone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.color(\.fg))
                .frame(maxWidth: 420)
            if case let .failed(message) = model.state {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.color(\.deadline))
                    .frame(maxWidth: 420)
            }
            Button("Choose Folder…") { isPicking = true }
                .buttonStyle(.borderedProminent)
                .tint(theme.color(\.accent))
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .font(.system(size: 13))
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.color(\.bg))
        .folderImporter(isPresented: $isPicking, model: model)
    }
}

extension View {
    /// The system folder picker; the chosen folder replaces the current one.
    func folderImporter(isPresented: Binding<Bool>, model: AppModel) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result {
                Task { await model.choose(folder) }
            }
        }
    }
}
