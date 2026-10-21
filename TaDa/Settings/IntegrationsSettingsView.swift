// Settings ▸ Integrations: the Show events and Show reminders switches, then the calendars and the Reminders lists side by
// side, ticked per account, or what to do when access is denied.
#if os(macOS)
import AppKit
import SwiftUI

struct IntegrationsSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    private var store: IntegrationsStore { model.integrations }

    var body: some View {
        SettingsPage(title: "Integrations", spacing: 18) {
            VStack(spacing: 0) {
                ForEach(IntegrationsStore.Kind.allCases, id: \.self) { kind in
                    if kind != .events { Hairline() }
                    switchRow(kind)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
            HStack(alignment: .top, spacing: 16) {
                ForEach(IntegrationsStore.Kind.allCases, id: \.self) { kind in
                    panel(kind)
                }
            }
        }
    }

    private func switchRow(_ kind: IntegrationsStore.Kind) -> some View {
        let access = store.access(kind)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.toggleLabel)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color(\.strong))
                Text(kind.macHint)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.muted))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(kind.toggleLabel, isOn: Binding(
                get: { access == .granted || access == .asking },
                set: { on in Task { await store.setOn(on, kind) } }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(theme.color(\.accent))
                .disabled(access == .asking || !store.canAsk(kind))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func panel(_ kind: IntegrationsStore.Kind) -> some View {
        let access = store.access(kind)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(kind.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color(\.strong))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let status = access.status {
                    HStack(spacing: 6) {
                        Circle().fill(theme.color(access.statusDot)).frame(width: 7, height: 7)
                        Text(status)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.muted))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Hairline()
            switch access {
            case .granted: choices(kind)
            case .denied: denied(kind)
            case .asking: note("Waiting for access…")
            case .off: note("Turn on \(kind.toggleLabel) to choose \(kind.choiceNoun).")
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
        .opacity(access == .off ? 0.6 : 1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind.name)
    }

    private func choices(_ kind: IntegrationsStore.Kind) -> some View {
        let sources = store.sources(kind)
        let all = sources.flatMap(\.calendars)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sources) { source in
                    SectionLabel(title: source.title)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    ForEach(source.calendars) { calendar in
                        CalendarTick(calendar: calendar, isOn: !store.isHidden(calendar.id, kind)) {
                            store.setHidden(!store.isHidden(calendar.id, kind), calendar.id, kind)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 8)
            Hairline()
            Text("\(all.count { !store.isHidden($0.id, kind) }) of \(all.count) shown")
                .font(.system(size: 12))
                .foregroundStyle(theme.color(\.muted))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
    }

    private func denied(_ kind: IntegrationsStore.Kind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(theme.color(\.deadline))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ta Da can’t see your \(kind.noun).")
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.color(\.strong))
                    Text("Open System Settings ▸ Privacy & Security ▸ \(kind.name) and turn on Ta Da.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingsButton("Open System Settings") { NSWorkspace.shared.open(kind.privacySettingsURL) }
                .padding(.leading, 26)
        }
        .padding(14)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(theme.color(\.muted))
            .padding(14)
    }
}

/// A calendar or list with a tick box in its own colour.
private struct CalendarTick: View {
    let calendar: IntegrationsStore.ListChoice
    let isOn: Bool
    let toggle: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let color = Color(calendarHex: calendar.color)
        Button(action: toggle) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? color : .clear)
                    .strokeBorder(color, lineWidth: 1.5)
                    .frame(width: 15, height: 15)
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                .accessibilityHidden(true)
                        }
                    }
                Text(calendar.title)
                    .foregroundStyle(theme.color(isOn ? \.fg : \.muted))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOn ? "Shown" : "Hidden")
        .accessibilityAddTraits(.isToggle)
    }
}

#Preview {
    IntegrationsSettingsView(model: AppModel())
}
#endif
