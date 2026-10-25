// Settings ▸ Integrations on iPhone: the Show events and Show reminders switches, then the calendars and the Reminders
// lists with checkmarks under each account, or what to do when access is denied.
#if os(iOS)
import SwiftUI

struct PhoneIntegrationsScreen: View {
    let store: IntegrationsStore
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Group {
                Section {
                    ForEach(IntegrationsStore.Kind.allCases, id: \.self) { kind in
                        let access = store.access(kind)
                        Toggle(isOn: Binding(get: { access == .granted || access == .asking },
                                             set: { on in Task { await store.setOn(on, kind) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.toggleLabel).foregroundStyle(theme.color(\.fg))
                                Text(kind.phoneHint)
                                    .scaledFont(size: 13)
                                    .foregroundStyle(theme.color(\.muted))
                            }
                        }
                        .disabled(access == .asking || !store.canAsk(kind))
                    }
                }
                ForEach(IntegrationsStore.Kind.allCases, id: \.self) { kind in
                    section(kind)
                }
            }
            .listRowBackground(theme.color(\.code))
        }
        .scrollContentBackground(.hidden)
        .background(theme.color(\.bg))
        .tint(theme.color(\.accent))
        .navigationTitle("Integrations")
    }

    private func section(_ kind: IntegrationsStore.Kind) -> some View {
        let access = store.access(kind)
        return Section {
            switch access {
            case .granted:
                ForEach(store.sources(kind)) { source in
                    Text(source.title)
                        .textCase(.uppercase)
                        .scaledFont(size: 12, weight: .semibold)
                        .tracking(0.7)
                        .foregroundStyle(theme.color(\.muted))
                        .padding(.top, 6)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(source.calendars) { tick($0, kind) }
                }
            case .denied:
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ta Da can’t see your \(kind.noun).")
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.color(\.strong))
                        Text("Open Settings ▸ Apps ▸ Ta Da and turn on \(kind.name).")
                            .scaledFont(size: 15)
                            .foregroundStyle(theme.color(\.fg))
                    }
                } icon: {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(theme.color(\.deadline))
                }
                Button("Open Settings") { openURL(kind.privacySettingsURL) }
                    .foregroundStyle(theme.color(\.accent))
            case .asking:
                Text("Waiting for access…").foregroundStyle(theme.color(\.muted))
            case .off:
                Text("Turn on \(kind.toggleLabel) to choose \(kind.choiceNoun).")
                    .scaledFont(size: 15)
                    .foregroundStyle(theme.color(\.muted))
            }
        } header: {
            HStack {
                Text(kind.name)
                Spacer()
                if let status = access.status {
                    HStack(spacing: 6) {
                        Circle().fill(theme.color(access.statusDot)).frame(width: 7, height: 7)
                        Text(status).textCase(nil)
                    }
                }
            }
        }
        .opacity(access == .off ? 0.6 : 1)
    }

    private func tick(_ calendar: IntegrationsStore.ListChoice, _ kind: IntegrationsStore.Kind) -> some View {
        let isOn = !store.isHidden(calendar.id, kind)
        return Button {
            store.setHidden(isOn, calendar.id, kind)
        } label: {
            HStack(spacing: 12) {
                Circle().fill(Color(calendarHex: calendar.color)).frame(width: 12, height: 12)
                Text(calendar.title)
                    .foregroundStyle(theme.color(isOn ? \.fg : \.muted))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color(\.accent))
                    .opacity(isOn ? 1 : 0)
                    .frame(width: 20, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOn ? "Shown" : "Hidden")
        .accessibilityAddTraits(.isToggle)
    }
}
#endif
