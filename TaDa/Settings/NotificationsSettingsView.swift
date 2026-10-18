// Settings ▸ Notifications: the Badges switch, or what to do when badges are turned off in System Settings.
#if os(macOS)
import AppKit
import SwiftUI

struct NotificationsSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    private var store: NotificationsStore { model.notifications }

    var body: some View {
        SettingsPage(title: "Notifications", summary: "What Ta Da shows outside its window.", spacing: 18) {
            VStack(spacing: 0) {
                switchRow
                if store.access == .denied {
                    Hairline()
                    denied
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
        }
    }

    private var switchRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Badges")
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color(\.strong))
                Text("The Dock icon counts the open tasks due or at their deadline today or earlier, as in today's Agenda")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.muted))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Badges", isOn: Binding(
                get: { [.on, .asking].contains(store.access) },
                set: { on in Task { await store.setOn(on) } }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(theme.color(\.accent))
                .disabled(store.access == .asking || store.access == .denied)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(theme.color(\.deadline))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ta Da can’t show badges.")
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.color(\.strong))
                    Text("Open System Settings ▸ Notifications ▸ Ta Da and turn on Allow notifications and Badge application icon.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingsButton("Open System Settings") { NSWorkspace.shared.open(NotificationsStore.settingsURL) }
                .padding(.leading, 26)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NotificationsSettingsView(model: AppModel())
}
#endif
