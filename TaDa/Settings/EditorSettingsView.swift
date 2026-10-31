// Settings ▸ Editor: the Autocomplete switches for brackets, text formatting, wikilinks and embeds, and tags, and the task checkboxes on links.
#if os(macOS)
import SwiftUI

struct EditorSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Editor") {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Autocomplete")
                VStack(spacing: 0) {
                    row("Brackets", markers: ["( )", "[ ]", "{ }"], isOn: $model.autocomplete.brackets)
                    Hairline()
                    row("Text formatting", markers: ["** **", "* *", "_ _", "~~ ~~", "== ==", "` `"], isOn: $model.autocomplete.formatting)
                    Hairline()
                    row("Wikilinks and embeds", markers: ["[[ ]]", "![[ ]]"], isOn: $model.autocomplete.wikiLinks)
                    Hairline()
                    row("Tags", markers: ["#"], isOn: $model.autocomplete.tags)
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Links")
                row("Task checkboxes on links", isOn: $model.taskLinkBoxes)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
            }
        }
    }

    private func row(_ title: String, markers: [String] = [], isOn: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color(\.strong))
                if !markers.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(markers, id: \.self) { marker in
                            Text(marker)
                                .font(.system(size: 11.5).monospaced())
                                .foregroundStyle(theme.color(\.accent))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .background(theme.color(\.code), in: .rect(cornerRadius: 5))
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(theme.color(\.accent))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    EditorSettingsView(model: AppModel())
}
#endif
