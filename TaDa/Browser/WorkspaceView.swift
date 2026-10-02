// The area right of the sidebar. M5: each domain's header, a plain list and its empty state.
// M6 replaces the plain lists with TaskListView, AgendaView and ProjectBrowserView.
import SwiftUI
import TaDaCore

struct WorkspaceView: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if model.state == .loading {
                ProgressView("Reading \(model.folderDisplayName)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.index.items.isEmpty {
                EmptyState(systemImage: "doc.badge.plus", title: "No Ta Da files yet",
                           message: "Nothing in “\(model.folderDisplayName)” has `type: task` or `type: project` frontmatter.")
            } else {
                domain
            }
        }
        .foregroundStyle(theme.color(\.fg))
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.color(\.bg))
    }

    @ViewBuilder private var domain: some View {
        let index = model.index, today = model.today
        switch model.domain {
        case .today:
            screen(DomainHeader(title: "Today", systemImage: "star.fill", tint: \.due),
                   rows: index.today(today).map { Row(item: $0, detail: where_($0)) },
                   empty: EmptyState(systemImage: "star", title: "Nothing due today",
                                     message: "Tasks due or at their deadline today, or overdue, show here."))
        case .upcoming:
            screen(DomainHeader(title: "Upcoming", systemImage: "calendar", tint: \.deadline),
                   rows: index.upcoming(after: today).map {
                       Row(id: $0.id, item: $0.item, detail: "\($0.date.formatted(.weekdayDayMonth)) · \($0.kind == .due ? "due" : "deadline")")
                   },
                   empty: EmptyState(systemImage: "calendar", title: "Nothing scheduled",
                                     message: "Open tasks with a due date or deadline after today show here."))
        case .loose:
            screen(DomainHeader(title: "Loose tasks", systemImage: "tray", tint: \.accent),
                   rows: index.loose().map { Row(item: $0, detail: $0.properties.status.rawValue) },
                   empty: EmptyState(systemImage: "tray", title: "No loose tasks",
                                     message: "Open tasks that don’t belong to a project show here."))
        case let .project(path):
            if let project = index[path] {
                let progress = index.activeProjects().first { $0.project.path == path }
                screen(DomainHeader(title: project.title, ring: progress?.fraction ?? 1),
                       rows: index.tasks(in: project).map { Row(item: $0, detail: $0.properties.status.rawValue) },
                       empty: EmptyState(systemImage: "checklist", title: "No tasks yet",
                                         message: "Tasks whose `project` is “[[\(project.title)]]” show here."))
            } else {
                EmptyState(systemImage: "questionmark.folder", title: "Project not found",
                           message: "This project’s file is no longer in the folder.")
            }
        }
    }

    private func where_(_ task: Item) -> String {
        model.index.project(of: task)?.title ?? "Loose task"
    }

    private func screen(_ header: DomainHeader, rows: [Row], empty: EmptyState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if rows.isEmpty {
                empty
            } else {
                List(rows) { row in
                    HStack(spacing: 10) {
                        Text(row.item.title)
                            .font(.system(size: 13.5))
                            .strikethrough(row.item.properties.status == .done)
                            .foregroundStyle(theme.color(row.item.properties.status == .done ? \.muted : \.fg))
                        Spacer(minLength: 12)
                        Text(row.detail).font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted))
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(theme.color(\.border))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 30)
            }
        }
    }

    private struct Row: Identifiable {
        var id: String
        var item: Item
        var detail: String

        init(id: String? = nil, item: Item, detail: String) {
            self.id = id ?? item.path
            self.item = item
            self.detail = detail
        }
    }
}

/// A domain's title row: an icon (or a project's progress ring) and a large title.
struct DomainHeader: View {
    let title: String
    var systemImage: String? = nil
    var tint: KeyPath<Theme, NSColor> = \.accent
    /// Shown instead of an icon for a project.
    var ring: Double? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            if let ring {
                ProgressRing(fraction: ring).scaleEffect(1.6).frame(width: 24, height: 24)
            } else if let systemImage {
                Image(systemName: systemImage).font(.system(size: 20))
            }
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.26)
                .foregroundStyle(theme.color(\.strong))
                .accessibilityAddTraits(.isHeader)
        }
        .foregroundStyle(theme.color(tint))
        .padding(.horizontal, 40)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

/// A centred message for an empty domain or folder.
struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: LocalizedStringKey
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.color(\.muted))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.color(\.strong))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.color(\.muted))
                .frame(maxWidth: 360)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension LocalDate {
    enum Style {
        /// "Sat 3 Oct"
        case weekdayDayMonth
    }

    func formatted(_ style: Style) -> String {
        switch style {
        case .weekdayDayMonth:
            date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }
}
