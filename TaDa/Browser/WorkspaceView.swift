// The area right of the sidebar: a domain's list beside the selected document, Upcoming's month view
// when nothing is selected, or a project's own page.
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
        switch model.domain {
        case .today:
            split { TaskListView(model: model, kind: .today).id(AppModel.Domain.today) }
        case .loose:
            split { TaskListView(model: model, kind: .loose).id(AppModel.Domain.loose) }
        case .upcoming:
            if model.selection == nil {
                VStack(alignment: .leading, spacing: 0) {
                    upcomingHeader(showsLegend: true).padding(.horizontal, 40)
                    HStack(alignment: .top, spacing: 40) {
                        AgendaView(model: model, style: .wide)
                        ScrollView { MonthCalendarView(model: model) }.scrollIndicators(.never).frame(width: 300)
                    }
                    .padding(.horizontal, 40)
                }
            } else {
                split {
                    VStack(alignment: .leading, spacing: 0) {
                        upcomingHeader(showsLegend: false).padding(.horizontal, 28)
                        AgendaView(model: model, style: .column)
                    }
                }
            }
        case let .project(path):
            if let project = model.index[path] {
                if model.selection == path {
                    DocumentArea(model: model)
                } else {
                    split { ProjectBrowserView(model: model, project: project) }
                }
            } else {
                EmptyState(systemImage: "questionmark.folder", title: "Project not found",
                           message: "This project’s file is no longer in the folder.")
            }
        }
    }

    private func upcomingHeader(showsLegend: Bool) -> some View {
        DomainHeader(title: "Upcoming", systemImage: "calendar", tint: \.deadline) {
            if showsLegend {
                HStack(spacing: 16) {
                    Chip(systemImage: AgendaEntry.Kind.due.systemImage, tint: \.due, text: "dueDate")
                    Chip(systemImage: AgendaEntry.Kind.deadline.systemImage, tint: \.deadline, text: "deadline")
                }
            } else {
                Button("Month view") { model.selection = nil }.buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// A browser column and the document pane, with a rule between them.
    private func split(@ViewBuilder browser: () -> some View) -> some View {
        HStack(spacing: 0) {
            browser()
                .frame(minWidth: 320, idealWidth: 460, maxWidth: 460, maxHeight: .infinity, alignment: .topLeading)
            Hairline(axis: .vertical)
            DocumentArea(model: model)
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The selected file, or a prompt to pick one. M7 replaces this with the live document.
struct DocumentArea: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        if let path = model.selection, let item = model.index[path] {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.title)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(theme.color(\.strong))
                if let summary = item.summary { Text(summary).font(.system(size: 14)) }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyState(systemImage: "doc.text", title: "No task selected", message: "Pick a task to read and edit it here.")
        }
    }
}
