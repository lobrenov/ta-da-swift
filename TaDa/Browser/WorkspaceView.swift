// The area right of the sidebar: a domain's list beside the selected document, Upcoming's month view
// when nothing is selected, or a project's or area's own page.
#if os(macOS)
import SwiftUI
import TaDaCore

struct WorkspaceView: View {
    let model: AppModel
    @Environment(\.theme) private var theme
    @State private var splitWidth: CGFloat = 0

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
        case .agenda:
            split { TaskListView(model: model, kind: .today).id(AppModel.Domain.agenda) }
        case .loose:
            split { TaskListView(model: model, kind: .loose).id(AppModel.Domain.loose) }
        case .trash:
            TrashView(model: model)
        case .logbook:
            split { LogbookView(model: model) }
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
        case let .tag(path):
            split { TagBrowserView(model: model, path: path).id(model.domain) }
        case let .folder(path):
            split { FolderBrowserView(model: model, folder: path).id(model.domain) }
        }
    }

    /// The browser column, the rule and the document pane at their narrowest.
    nonisolated static let minWidth: CGFloat = 320 + 1 + 360

    /// A browser column and the document pane, with a rule between them that drags to resize the column.
    private func split(@ViewBuilder browser: () -> some View) -> some View {
        SplitLayout(browserWidth: model.browserWidth.map { CGFloat($0) }) {
            browser()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Hairline(axis: .vertical)
                .overlay {
                    Color.clear
                        .frame(width: 9)
                        .contentShape(Rectangle())
                        .pointerStyle(.columnResize)
                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(SplitLayout.space))
                            .onChanged { model.browserWidth = Double(SplitLayout.clamp(round($0.location.x), in: splitWidth)) })
                }
                .zIndex(1)
            DocumentPane(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .coordinateSpace(.named(SplitLayout.space))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { splitWidth = $0 }
    }
}

/// The browser column, a rule and the document pane. The browser is `browserWidth` wide, at least 260, or else half
/// the width from 320 to 460; the document pane keeps at least 360.
private struct SplitLayout: Layout {
    var browserWidth: CGFloat?

    static let space = "split"
    static let minBrowser: CGFloat = 260

    /// A dragged width, at least `minBrowser` and leaving the document pane 360 of the split's width.
    static func clamp(_ width: CGFloat, in total: CGFloat) -> CGFloat { max(minBrowser, min(width, total - 1 - 360)) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: max(proposal.width ?? 1040, WorkspaceView.minWidth), height: proposal.height ?? 600)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let preferred = browserWidth ?? max(320, min((bounds.width - 1) / 2, 460))
        let browser = max(Self.minBrowser, min(preferred, bounds.width - 1 - 360))
        var x = bounds.minX
        for (subview, width) in zip(subviews, [browser, 1, max(0, bounds.width - browser - 1)]) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
}
#endif
