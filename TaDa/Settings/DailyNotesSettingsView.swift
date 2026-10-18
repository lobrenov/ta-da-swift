// Settings ▸ Daily notes: the folder, file name and template for daily notes, and the same for week notes, which can be switched off.
#if os(macOS)
import SwiftUI
import TaDaCore

struct DailyNotesSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Daily notes", summary: "One note a day, and one a week, kept as plain markdown in your folder.") {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Daily")
                VStack(spacing: 0) {
                    folderRow($model.dailyFolder)
                    Hairline()
                    nameRow("YYYY-MM-DD", example: model.dailyNoteExample)
                    Hairline()
                    templateRow($model.dailyTemplate)
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Week notes")
                VStack(spacing: 0) {
                    HStack {
                        Text("Show a note for each week")
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.color(\.strong))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Week notes", isOn: $model.weekNotes)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(theme.color(\.accent))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    Group {
                        Hairline()
                        folderRow($model.weekFolder)
                        Hairline()
                        nameRow("GGGG-[W]WW", example: model.weekNoteExample)
                        Hairline()
                        templateRow($model.weekTemplate)
                    }
                    .disabled(!model.weekNotes)
                    .opacity(model.weekNotes ? 1 : 0.45)
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
                Text("Each week opens with its note in the Agenda.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.muted))
            }
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .foregroundStyle(theme.color(\.muted))
                .frame(width: 84, alignment: .leading)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 46)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func folderRow(_ folder: Binding<String>) -> some View {
        row("Folder") {
            FolderField(folder: folder, choices: model.noteFolderPaths)
        }
    }

    private func nameRow(_ pattern: String, example: String) -> some View {
        row("File name") {
            Text(pattern)
                .font(.system(size: 12).monospaced())
                .foregroundStyle(theme.color(\.accent))
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(theme.color(\.code), in: .rect(cornerRadius: 5))
            Text("e.g. \(example)")
                .foregroundStyle(theme.color(\.muted))
        }
    }

    private func templateRow(_ template: Binding<String?>) -> some View {
        let notes = model.templateChoices
        let missing = model.missingTemplate(template.wrappedValue)
        let title = missing?.missingTemplateLabel
            ?? template.wrappedValue.map { path in notes.first { $0.path == path }?.title ?? Item.title(ofPath: path) } ?? "None"
        return row("Template") {
            Menu {
                Picker("Template", selection: template) {
                    Text("None").tag(String?.none)
                    if let missing {
                        Text(missing.missingTemplateLabel).tag(String?.some(missing))
                    }
                    ForEach(notes) { Text($0.path.dropLast(3)).tag(String?.some($0.path)) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack {
                    Text(title)
                        .foregroundStyle(theme.color(template.wrappedValue == nil || missing != nil ? \.muted : \.strong))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.color(\.muted))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(theme.color(\.code), in: .rect(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)))
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Template")
            .accessibilityValue(title)
        }
    }
}

/// A folder path typed into a field, committed on Return or when the field loses focus, with a menu of the vault's folders.
private struct FolderField: View {
    @Binding var folder: String
    let choices: [String]
    @State private var draft = ""
    @FocusState private var isFocused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            TextField("Folder", text: $draft, prompt: Text("Vault folder").foregroundStyle(theme.color(\.muted)))
                .textFieldStyle(.plain)
                .font(.system(size: 12).monospaced())
                .focused($isFocused)
                .onSubmit(commit)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(theme.color(\.code), in: .rect(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(isFocused ? \.accent : \.border)))
            Menu {
                Button("Vault root") { folder = "" }
                ForEach(choices, id: \.self) { path in
                    Button(path) { folder = path }
                }
            } label: {
                Image(systemName: "folder")
                    .foregroundStyle(theme.color(\.muted))
                    .frame(width: 30, height: 30)
                    .background(theme.color(\.code), in: .rect(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)))
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Choose a folder")
        }
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

#Preview {
    DailyNotesSettingsView(model: AppModel())
}
#endif
