// Settings window: theme and folder.
import SwiftUI
import TaDaCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var isPicking = false

    var body: some View {
        Form {
            Picker("Theme", selection: $model.themeName) {
                ForEach(Theme.all) { Text($0.name).tag($0.name) }
            }
            LabeledContent("Folder") {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(model.vault?.root.path(percentEncoded: false) ?? "None")
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                    Button("Change Folder…") { isPicking = true }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .folderImporter(isPresented: $isPicking, model: model)
    }
}

#Preview {
    SettingsView(model: AppModel())
}
