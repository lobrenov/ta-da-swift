// Settings window: a themed sidebar with the Vault, Themes, Editor, Daily notes, Integrations, Notifications and Hotkeys pages, and the parts the pages share.
#if os(macOS)
import SwiftUI
import TaDaCore

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsWindow(model: model)
            .themed(by: model)
    }
}

private struct SettingsWindow: View {
    @Bindable var model: AppModel
    @State private var page = Page.vault
    @Environment(\.theme) private var theme

    enum Page { case vault, themes, editor, dailyNotes, integrations, notifications, hotkeys }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                row(.vault, "Vault", systemImage: "folder", tint: \.accent)
                row(.themes, "Themes", systemImage: "paintpalette", tint: \.link)
                row(.editor, "Editor", systemImage: "pencil", tint: \.doing)
                row(.dailyNotes, "Daily notes", systemImage: "calendar.badge.clock", tint: \.done)
                row(.integrations, "Integrations", systemImage: "calendar", tint: \.deadline)
                row(.notifications, "Notifications", systemImage: "app.badge", tint: \.blocked)
                row(.hotkeys, "Hotkeys", systemImage: "keyboard", tint: \.due)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .frame(width: 200)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(theme.color(\.side))
            Hairline(axis: .vertical)
            ScrollView {
                switch page {
                case .vault: VaultSettingsView(model: model)
                case .themes: ThemeSettingsView(model: model)
                case .editor: EditorSettingsView(model: model)
                case .dailyNotes: DailyNotesSettingsView(model: model)
                case .integrations: IntegrationsSettingsView(model: model)
                case .notifications: NotificationsSettingsView(model: model)
                case .hotkeys: HotkeysSettingsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.color(\.bg))
        }
        .overlay(alignment: .top) { Hairline() }
        .foregroundStyle(theme.color(\.fg))
        .font(.system(size: 13))
        .frame(width: 900, height: 594)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .containerBackground(theme.color(\.side), for: .window)
    }

    private func row(_ page: Page, _ title: String, systemImage: String, tint: KeyPath<Theme, NSColor>) -> some View {
        SidebarRow(selected: self.page == page, height: 32, count: nil) {
            self.page = page
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(theme.color(tint))
                .frame(width: 16)
                .accessibilityHidden(true)
        } label: {
            Text(title)
        }
    }
}

/// A settings page: its title above its sections.
struct SettingsPage<Content: View>: View {
    let title: String
    var spacing: CGFloat = 22
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.color(\.strong))
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(.horizontal, 36)
        .padding(.top, 26)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The uppercase label over a group: PROJECTS in the sidebar, the file inspector's sections, FOLDERS IN THE VAULT.
struct SectionLabel: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.66)
            .foregroundStyle(theme.color(\.muted))
            .accessibilityAddTraits(.isHeader)
    }
}

/// A secondary button on `code` with a hairline border.
struct SettingsButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(ActionButtonStyle(height: 28, fill: \.code))
    }
}

#Preview {
    SettingsView(model: AppModel())
}
#endif
