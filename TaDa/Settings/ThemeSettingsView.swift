// Settings ▸ Themes: the appearance, the theme set (or a scheme per appearance), previews of the pair
// and the bundled sets.
import SwiftUI

struct ThemeSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Themes",
                     summary: "Each theme set pairs a light and a dark iTerm2 scheme. Ta Da switches between them with your Mac’s appearance.",
                     spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    label("Appearance")
                    AppearancePicker(selection: $model.appearance)
                    Text(model.appearance == .system
                         ? "Following macOS · currently \(model.systemIsDark ? "Dark" : "Light")"
                         : "Ignores the macOS setting")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.color(\.muted))
                }
                HStack(spacing: 12) {
                    if model.usesSchemePerAppearance {
                        label("Light scheme")
                        ThemeMenu(title: "Light scheme", selection: model.lightScheme.name, options: Theme.all.map(\.name)) {
                            model.lightScheme = Theme.named($0) ?? model.lightScheme
                        }
                        .frame(width: 220)
                        Text("Dark scheme")
                            .foregroundStyle(theme.color(\.muted))
                            .fixedSize()
                            .padding(.leading, 8)
                        ThemeMenu(title: "Dark scheme", selection: model.darkScheme.name, options: Theme.all.map(\.name)) {
                            model.darkScheme = Theme.named($0) ?? model.darkScheme
                        }
                        .frame(maxWidth: 200)
                    } else {
                        label("Theme set")
                        ThemeMenu(title: "Theme set", selection: model.themeSet.name, options: ThemeSet.all.map(\.name)) {
                            model.choose(ThemeSet.named($0) ?? model.themeSet)
                        }
                        .frame(width: 220)
                    }
                }
                Toggle("Use a different scheme for each appearance", isOn: $model.usesSchemePerAppearance)
                    .toggleStyle(.checkbox)
                    .tint(theme.color(\.accent))
                    .padding(.leading, 104)
            }

            HStack(spacing: 14) {
                SchemeCard(slot: "Light", systemImage: "sun.max", scheme: model.shownLightScheme, inUse: !model.isDark)
                SchemeCard(slot: "Dark", systemImage: "moon", scheme: model.shownDarkScheme, inUse: model.isDark)
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(title: "Bundled theme sets")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                    ForEach(ThemeSet.all) { set in
                        ThemeSetButton(set: set, selected: !model.usesSchemePerAppearance && set == model.themeSet) {
                            model.choose(set)
                        }
                    }
                }
            }
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(theme.color(\.muted))
            .frame(width: 92, alignment: .leading)
    }
}

/// System, Light, Dark as a segmented control.
private struct AppearancePicker: View {
    @Binding var selection: Appearance
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Appearance.allCases) { appearance in
                let selected = appearance == selection
                Button { selection = appearance } label: {
                    Text(appearance.rawValue)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(theme.color(selected ? \.strong : \.fg))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(selected ? theme.color(\.bg) : .clear, in: .rect(cornerRadius: 5))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(theme.color(\.surface), in: .rect(cornerRadius: 7))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }
}

/// A pop-up menu of names, drawn as a themed field.
private struct ThemeMenu: View {
    let title: String
    let selection: String
    let options: [String]
    let pick: (String) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            Picker(title, selection: Binding { selection } set: { pick($0) }) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack {
                Text(selection)
                    .foregroundStyle(theme.color(\.strong))
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
        .accessibilityLabel(title)
        .accessibilityValue(selection)
    }
}

/// One scheme of the pair: its slot and name over a small preview of the app in it.
private struct SchemeCard: View {
    let slot: String
    let systemImage: String
    let scheme: Theme
    let inUse: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                Text(slot)
                Text(scheme.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color(\.fg))
                Spacer()
                if inUse {
                    Text("In use")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.color(\.strong))
                        .padding(.horizontal, 8)
                        .background(theme.color(\.surface), in: .capsule)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(theme.color(\.muted))
            SchemePreview(scheme: scheme)
                .frame(height: 132)
                .clipShape(.rect(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(theme.color(inUse ? \.accent : \.border), lineWidth: inUse ? 2 : 1))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A miniature window in a scheme: sidebar rows, a Today list and a line of YAML.
private struct SchemePreview: View {
    let scheme: Theme

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in
                        Circle().fill(color).frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 4)
                sidebarRow(\.due, line: \.strong, width: nil, selected: true)
                sidebarRow(\.deadline, line: \.muted, width: 26, selected: false)
                sidebarRow(\.accent, line: \.muted, width: 30, selected: false)
                sidebarRow(\.done, line: \.muted, width: 22, selected: false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(width: 78)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(scheme.color(\.side))
            .overlay(alignment: .trailing) { Rectangle().fill(scheme.color(\.border)).frame(width: 1) }

            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(scheme.color(\.strong))
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(scheme.color(\.doing), lineWidth: 1.5)
                        .overlay { RoundedRectangle(cornerRadius: 1).fill(scheme.color(\.doing)).frame(width: 4, height: 4) }
                        .frame(width: 11, height: 11)
                    Text("Write release notes").foregroundStyle(scheme.color(\.strong))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(scheme.color(\.surface), in: .rect(cornerRadius: 5))
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(scheme.color(\.muted), lineWidth: 1.5)
                        .frame(width: 11, height: 11)
                    Text("Submit timesheet").foregroundStyle(scheme.color(\.fg))
                    Spacer(minLength: 0)
                    Circle().fill(scheme.color(\.due)).frame(width: 6, height: 6)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(scheme.color(\.done))
                        .frame(width: 11, height: 11)
                    Text("Audit the global file")
                        .strikethrough()
                        .foregroundStyle(scheme.color(\.muted))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                Text("\(Text("project").foregroundStyle(scheme.color(\.accent)))\(Text(": [[").foregroundStyle(scheme.color(\.muted)))\(Text("Ta Da").foregroundStyle(scheme.color(\.link)))\(Text("]]").foregroundStyle(scheme.color(\.muted)))")
                    .font(.system(size: 10).monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(scheme.color(\.bg))
    }

    private func sidebarRow(_ glyph: KeyPath<Theme, NSColor>, line: KeyPath<Theme, NSColor>,
                            width: CGFloat?, selected: Bool) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(scheme.color(glyph)).frame(width: 6, height: 6)
            Capsule().fill(scheme.color(line)).frame(width: width, height: 4)
            if width != nil { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 4)
        .frame(height: 14)
        .background(selected ? scheme.color(\.surface) : .clear, in: .rect(cornerRadius: 4))
    }
}

/// A bundled set: its light and dark grounds side by side, and its name.
private struct ThemeSetButton: View {
    let set: ThemeSet
    let selected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 0) {
                    half(set.light)
                    half(set.dark)
                }
                .frame(height: 40)
                .clipShape(.rect(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(theme.color(selected ? \.accent : \.border), lineWidth: selected ? 2 : 1))
                Text(set.name)
                    .font(.system(size: 11, weight: selected ? .bold : .medium))
                    .foregroundStyle(theme.color(selected ? \.strong : \.fg))
                    .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(set.name) theme set")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func half(_ scheme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(scheme.color(\.fg)).frame(height: 4)
            HStack(spacing: 2) {
                ForEach([\Theme.due, \.accent, \.done], id: \.self) { token in
                    Circle().fill(scheme.color(token)).frame(width: 5, height: 5)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(scheme.color(\.bg))
    }
}

#Preview {
    ThemeSettingsView(model: AppModel())
}
