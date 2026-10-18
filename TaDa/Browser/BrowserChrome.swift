// Pieces shared by the browser lists: the column layout, domain header, group headers and empty states.
import SwiftUI
import TaDaCore

#if os(macOS)
/// A browser list beside the document pane: its header, then its content scrolling below. `paths` are the files of its
/// rows from top to bottom, for the arrow keys; `empty`, when set, takes the content's place.
struct BrowserColumn<Header: View, Content: View>: View {
    let model: AppModel
    let paths: [String]
    /// Between the content's groups, days or rows.
    let spacing: CGFloat
    var empty: EmptyState? = nil
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 14)
            if let empty {
                empty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: spacing) { content }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }
            }
        }
        .arrowKeySelection(model, paths: paths, allowsMultipleSelection: true)
    }
}
#endif

/// A domain's title row: an icon, a large title and optional trailing content.
struct DomainHeader<Trailing: View>: View {
    let title: String
    var systemImage: String? = nil
    var tint: KeyPath<Theme, PlatformColor> = \.accent
    @ViewBuilder var trailing: Trailing
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 20)).accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.26)
                .foregroundStyle(theme.color(\.strong))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            trailing
                .font(.system(size: 12))
                .foregroundStyle(theme.color(\.muted))
        }
        .foregroundStyle(theme.color(tint))
    }
}

extension DomainHeader {
    /// A domain's header, with its title, symbol and tint.
    init(_ domain: AppModel.Domain, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: domain.title, systemImage: domain.systemImage, tint: domain.tint, trailing: trailing)
    }
}

extension DomainHeader where Trailing == EmptyView {
    init(title: String, systemImage: String? = nil, tint: KeyPath<Theme, PlatformColor> = \.accent) {
        self.init(title: title, systemImage: systemImage, tint: tint) { EmptyView() }
    }

    init(_ domain: AppModel.Domain) {
        self.init(domain) { EmptyView() }
    }
}

extension AppModel.Domain {
    /// The sidebar's name for the domain, or the project's, area's or folder's title.
    var title: String {
        switch self {
        case .agenda: "Agenda"
        case .loose: "Loose tasks"
        case .logbook: "Logbook"
        case .trash: "Trash"
        case .project(let path), .area(let path): Item.title(ofPath: path)
        case .tag(let path): path.flatMap(Tag.init)?.leaf ?? "Untagged"
        case .folder(let path): path.isEmpty ? "Loose" : String(path.split(separator: "/").last ?? "")
        }
    }

    /// A project's symbol stands in for its progress ring where the ring doesn't fit, as in the file inspector.
    var systemImage: String {
        switch self {
        case .agenda: "calendar"
        case .loose: "tray"
        case .logbook: "book.closed"
        case .trash: "trash"
        case .project: "circle.dotted"
        case .area: "cube"
        case .tag(let path): path == nil ? "tag.slash" : "tag"
        case .folder(let path): path.isEmpty ? "tray" : "folder"
        }
    }

    var tint: KeyPath<Theme, PlatformColor> {
        switch self {
        case .agenda: \.due
        case .loose, .project: \.accent
        case .logbook: \.done
        case .trash: \.muted
        case .area: \.doing
        case .tag(let path): path == nil ? \.muted : \.accent
        case .folder: \.link
        }
    }
}

extension View {
    /// Makes a project's or area's group heading a button that shows its page.
    func opensPage(of parent: Item, _ model: AppModel) -> some View {
        Button { model.show(parent.properties.kind == .area ? .area(parent.path) : .project(parent.path)) } label: {
            contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A project's heading inside a list: its ring and title over a rule.
struct ProjectGroupHeader: View {
    let project: Item
    let progress: ProjectProgress
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ProgressRing(progress).foregroundStyle(theme.color(\.accent))
                Text(project.title).fontWeight(.semibold).foregroundStyle(theme.color(\.strong)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            Hairline()
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// An area's heading inside a list: its cube and title over a rule.
struct AreaGroupHeader: View {
    let area: Item
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                AreaIcon()
                Text(area.title).fontWeight(.semibold).foregroundStyle(theme.color(\.strong)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            Hairline()
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A project's heading under its area's: its ring and title, smaller and without a rule.
struct ProjectSubheader: View {
    let project: Item
    let progress: ProjectProgress
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ProgressRing(progress).foregroundStyle(theme.color(\.accent))
            Text(project.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.color(\.fg)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A muted group name with a count on the right, over a rule ("Open 6"). With `isExpanded`, a chevron before the
/// name points down when the group is open and right when it's folded, and clicking the header folds or opens it.
struct CountGroupHeader: View {
    let title: String
    let count: Int
    var isExpanded: Binding<Bool>? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 7) {
            if let isExpanded {
                Button { isExpanded.wrappedValue.toggle() } label: { label(expanded: isExpanded.wrappedValue) }
                    .buttonStyle(.plain)
                    .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
                    .accessibilityHint(isExpanded.wrappedValue ? "Folds the group" : "Opens the group")
            } else {
                label(expanded: nil)
            }
            Hairline()
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func label(expanded: Bool?) -> some View {
        HStack(spacing: 6) {
            if let expanded {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 12)
                    .accessibilityHidden(true)
            }
            Text(title).fontWeight(.semibold)
            Spacer()
            Text("\(count)").fontWeight(.medium).monospacedDigit()
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.color(\.muted))
        .padding(.leading, expanded == nil ? 10 : 6)
        .padding(.trailing, 10)
        .contentShape(.rect)
    }
}

/// A centred message for an empty domain or folder.
struct EmptyState: View {
    let systemImage: String
    let title: String
    var message: LocalizedStringKey?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.color(\.muted))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.color(\.strong))
            if let message {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.color(\.muted))
                    .frame(maxWidth: 360)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A 1pt line in the border colour, between columns or under a header.
struct Hairline: View {
    var axis = Axis.horizontal
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.color(\.border))
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}
