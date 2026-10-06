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
            } else if model.index.items.isEmpty, model.domain != .trash {
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
        if model.isSourceMode, model.document != nil {
            DocumentPane(model: model)
        } else if model.isSearching {
            split { SearchResultsView(model: model) }
        } else {
            domainLayout
        }
    }

    @ViewBuilder private var domainLayout: some View {
        switch model.domain {
        case .today:
            split { TaskListView(model: model, kind: .today).id(AppModel.Domain.today) }
        case .loose:
            split { TaskListView(model: model, kind: .loose).id(AppModel.Domain.loose) }
        case .trash:
            TrashView(model: model)
        case .upcoming:
            if model.selection == nil, model.multiSelection.isEmpty {
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
                    DocumentPane(model: model)
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
        DomainHeader(.upcoming) {
            if showsLegend {
                HStack(spacing: 16) {
                    ForEach([AgendaEntry.Kind.due, .deadline], id: \.self) { kind in
                        Chip(systemImage: kind.systemImage, tint: kind.tint, text: kind.key)
                    }
                }
            } else {
                Button("Month view") {
                    model.selection = nil
                    model.clearMultiSelection()
                }
                .buttonStyle(.plain)
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
            DocumentPane(model: model)
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
