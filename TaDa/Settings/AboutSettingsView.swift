// Settings ▸ About: the app's version and build, and the packages it ships with and their licences.
#if os(macOS)
import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.theme) private var theme

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

    var body: some View {
        SettingsPage(title: "About") {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Ta Da")
                VStack(spacing: 0) {
                    row("Version", Self.version)
                    Hairline()
                    row("Build", Self.build)
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Acknowledgements")
                VStack(spacing: 0) {
                    let all = Acknowledgement.all
                    ForEach(all.indices, id: \.self) { index in
                        if index > 0 { Hairline() }
                        package(all[index])
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
                .frame(width: 88, alignment: .leading)
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
