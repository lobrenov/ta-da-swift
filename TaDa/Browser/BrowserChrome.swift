// Pieces shared by the browser lists: the column layout, domain header, group headers, context filter and empty states.
import SwiftUI
import TaDaCore

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

/// A domain's title row: an icon (or a project's progress ring), a large title and optional trailing content.
struct DomainHeader<Trailing: View>: View {
    let title: String
    var systemImage: String? = nil
    var tint: KeyPath<Theme, NSColor> = \.accent
    /// Shown instead of an icon for a project.
    var ring: Double? = nil
    var size: CGFloat = 26
    @ViewBuilder var trailing: Trailing
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            if let ring {
                ProgressRing(fraction: ring).scaleEffect(size / 16).frame(width: size - 3, height: size - 3)
            } else if let systemImage {
                Image(systemName: systemImage).font(.system(size: size * 0.77)).accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: size, weight: .bold))
                .tracking(-size / 100)
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
    init(title: String, systemImage: String? = nil, tint: KeyPath<Theme, NSColor> = \.accent, ring: Double? = nil, size: CGFloat = 26) {
        self.init(title: title, systemImage: systemImage, tint: tint, ring: ring, size: size) { EmptyView() }
    }

    init(_ domain: AppModel.Domain) {
        self.init(domain) { EmptyView() }
    }
}

extension AppModel.Domain {
    /// The sidebar's name for the domain, or the project's title.
    var title: String {
        switch self {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .loose: "Loose tasks"
        case .trash: "Trash"
        case .project(let path): Item.title(ofPath: path)
        }
    }

    /// A project's symbol stands in for its progress ring where the ring doesn't fit, as in the file inspector.
    var systemImage: String {
        switch self {
        case .today: "star.fill"
        case .upcoming: "calendar"
        case .loose: "tray"
        case .trash: "trash"
        case .project: "circle.dotted"
        }
    }

    var tint: KeyPath<Theme, NSColor> {
        switch self {
        case .today: \.due
        case .upcoming: \.deadline
        case .loose, .project: \.accent
        case .trash: \.muted
        }
    }
}

/// A project's heading inside a list: its ring and title over a rule.
struct ProjectGroupHeader: View {
    let project: Item
    let fraction: Double
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ProgressRing(fraction: fraction).foregroundStyle(theme.color(\.accent))
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

/// A muted group name with a count on the right, over a rule ("Open 6").
struct CountGroupHeader: View {
    let title: String
    let count: Int
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Text("\(count)").fontWeight(.medium).monospacedDigit()
            }
            .font(.system(size: 12))
            .foregroundStyle(theme.color(\.muted))
            .padding(.horizontal, 10)
            Hairline()
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// "All" plus one pill per context; picking one filters the list.
struct ContextFilter: View {
    let contexts: [String]
    @Binding var selection: String?
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            pill("All", value: nil)
            ForEach(contexts, id: \.self) { pill($0, value: $0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by context")
    }

    private func pill(_ label: String, value: String?) -> some View {
        let on = selection == value
        return Button { selection = value } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.color(on ? \.strong : \.muted))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(on ? theme.color(\.surface) : .clear, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
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
                .accessibilityHidden(true)
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
