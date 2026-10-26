// Settings ▸ About: the app's version and build, and the packages it ships with and their licences.
#if os(macOS)
import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "About") {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Ta Da")
                VStack(spacing: 0) {
                    row("Version", Bundle.main.version)
                    Hairline()
                    row("Build", Bundle.main.build)
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Acknowledgements")
                VStack(spacing: 0) {
                    ForEach(Acknowledgement.all, id: \.url) { package in
                        if package.url != Acknowledgement.all.first?.url { Hairline() }
                        self.package(package)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .foregroundStyle(theme.color(\.muted))
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: 12).monospaced())
                .foregroundStyle(theme.color(\.strong))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func package(_ package: Acknowledgement) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(package.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color(\.strong))
                Text(package.url)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.muted))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(package.licence)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.color(\.muted))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(theme.color(\.code), in: .rect(cornerRadius: 5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    AboutSettingsView()
}
#endif
