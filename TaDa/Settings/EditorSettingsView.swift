// Settings ▸ Editor: the Autocomplete switches for brackets, text formatting, wikilinks and embeds, and tags.
#if os(macOS)
import SwiftUI

struct EditorSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Editor", summary: "How the editor helps as you type markdown.") {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Autocomplete")
                VStack(spacing: 0) {
                    row("Brackets", "Typing an opening bracket adds its closer.",
                        markers: ["( )", "[ ]", "{ }"], isOn: $model.autocomplete.brackets)
                    Hairline()
                    row("Text formatting", "Bold, italic, strikethrough, highlight and inline code markers come in pairs.",
                        markers: ["** **", "* *", "_ _", "~~ ~~", "== ==", "` `"], isOn: $model.autocomplete.formatting)
                    Hairline()
                    row("Wikilinks and embeds", "Typing [[ adds ]], for links and ![[ embeds.",
                        markers: ["[[ ]]", "![[ ]]"], isOn: $model.autocomplete.wikiLinks)
                    Hairline()
                    row("Tags", "Typing # and a letter lists the tags in use.",
                        markers: ["#"], isOn: $model.autocomplete.tags)
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
            }
        }
    }

    private func row(_ title: String, _ summary: String, markers: [String], isOn: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color(\.strong))
                Text(summary)
                    .foregroundStyle(theme.color(\.muted))
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
