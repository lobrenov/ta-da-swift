// The Logbook, pushed from the Other tab: the completed files not logged yet (logging tonight, or waiting for their
// project's open tasks), then the logged ones by day and month, with Log Now in the bottom bar. A row's box reopens
// a task, which goes back to `Ta Da/tasks/`; a tap opens the file.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneLogbookScreen: View {
    let model: AppModel
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let groups = LogbookGroup.groups(model.logbook, index: model.index, today: model.today)
        let waiting = groups.filter(\.isWaiting).map(\.items.count).reduce(0, +)
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { row($0) }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.title).scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.strong))
                        Spacer()
                        if let note = note(group.kind) {
                            Text(note).scaledFont(size: 13).foregroundStyle(theme.color(\.muted))
                        }
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background { theme.color(\.bg).ignoresSafeArea() }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Nothing logged yet", systemImage: AppModel.Domain.logbook.systemImage)
            }
        }
        .navigationTitle("Logbook")
        .navigationSubtitle("Completed files in \(Vault.logbookFolder)/")
        .background { TabBarHiddenOnTop() }
        .toolbar {
            if waiting > 0 {
                ToolbarItem(placement: .bottomBar) {
                    Text("\(waiting) completed today")
                        .scaledFont(size: 13)
                        .foregroundStyle(theme.color(\.muted))
                        .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button("Log Now") {
                    nav.play(.complete)
                    Task { await model.logNow() }
                }
                .buttonStyle(.glassProminent)
                .tint(theme.color(\.accent))
                .disabled(!model.hasFilesToLog)
            }
        }
    }

    /// A task's box (which reopens it) or a project's full ring, its struck title over its parent, and the day it was
    /// completed.
    private func note(_ kind: LogbookGroup.Kind) -> String? {
        switch kind {
        case .logsTonight: "Logs tonight"
        case .waitsForOpenTasks: nil
        case .logged: nil
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if item.properties.kind == .project {
                ProgressRing(fraction: 1)
                    .scaleEffect(20 / 14)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(theme.color(item.properties.status == .cancelled ? \.muted : \.done))
            } else {
                StatusCheckbox(status: item.properties.status, title: item.title, size: 24) {
                    nav.play(.pick)
                    Task { await model.toggleCompletion(item) }
                }
            }
            Button { nav.push(.file(item.path)) } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .scaledFont(size: 17, weight: item.properties.kind == .project ? .semibold : .regular)
                            .strikethrough()
                            .foregroundStyle(theme.color(\.muted))
                            .lineLimit(2)
                        Text(LogbookGroup.meta(item, index: model.index))
                            .scaledFont(size: 13)
                            .foregroundStyle(theme.color(\.muted))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(LogbookGroup.shortDate(item, today: model.today))
                        .scaledFont(size: 13)
                        .foregroundStyle(theme.color(\.muted))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.clear)
        .contextMenu { PhoneFileMenu(model: model, item: item) }
    }
}
#endif
