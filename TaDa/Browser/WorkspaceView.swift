// The area right of the sidebar: a domain's list beside the selected document, Upcoming's month view
// when nothing is selected, or a project's or area's own page.
#if os(macOS)
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
                           message: "Nothing in “\(model.folderDisplayName)” has `type: task`, `type: project` or `type: area` frontmatter.")
            } else {
                domain
            }
        }
        .foregroundStyle(theme.color(\.fg))
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.color(\.bg))
        .taskDragContainer(model)
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
                    upcomingHeader.padding(.horizontal, 40)
                    HStack(alignment: .top, spacing: 40) {
                        AgendaView(model: model, style: .wide)
                        ScrollView { MonthCalendarView(model: model) }.scrollIndicators(.never).frame(width: 300)
                    }
                    .padding(.horizontal, 40)
                }
            } else {
                split { AgendaView(model: model, style: .column) }
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
        case let .area(path):
            if let area = model.index[path] {
                if model.selection == path {
                    DocumentPane(model: model)
                } else {
                    split { AreaBrowserView(model: model, area: area) }
                }
            } else {
                EmptyState(systemImage: "questionmark.folder", title: "Area not found",
                           message: "This area’s file is no longer in the folder.")
            }
        }
    }

    /// Upcoming's header over the agenda and month calendar, with the dates' legend.
    private var upcomingHeader: some View {
        DomainHeader(.upcoming) {
            HStack(spacing: 16) {
                ForEach([AgendaEntry.Kind.due, .deadline], id: \.self) { kind in
                    Chip(systemImage: kind.systemImage, tint: kind.tint, text: kind.key)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// The browser column, the rule and the document pane at their narrowest.
    static let minWidth: CGFloat = 320 + 1 + 360

    /// A browser column and the document pane, with a rule between them.
    private func split(@ViewBuilder browser: () -> some View) -> some View {
        SplitLayout {
            browser()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Hairline(axis: .vertical)
            DocumentPane(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The browser column, a rule and the document pane: the browser takes half the width, from 320 to 460, leaving the
/// document pane at least 360.
private struct SplitLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: max(proposal.width ?? 1040, WorkspaceView.minWidth), height: proposal.height ?? 600)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let browser = max(320, min((bounds.width - 1) / 2, 460, bounds.width - 1 - 360))
        var x = bounds.minX
        for (subview, width) in zip(subviews, [browser, 1, max(0, bounds.width - browser - 1)]) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
}
#endif
