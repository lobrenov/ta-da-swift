// Sidebar: the three domains with counts, active projects with progress rings, and the folder line.
import SwiftUI
import TaDaCore

struct SidebarView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    row(.today, "Today", systemImage: "star.fill", tint: \.due, count: model.todayCount)
                    row(.upcoming, "Upcoming", systemImage: "calendar", tint: \.deadline, count: nil)
                    row(.loose, "Loose tasks", systemImage: "tray", tint: \.accent, count: model.looseCount)

                    Text("Projects")
                        .textCase(.uppercase)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.66)
                        .foregroundStyle(theme.color(\.muted))
                        .padding(.horizontal, 10)
                        .padding(.top, 20)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)

                    if model.projects.isEmpty {
                        Text("No active projects")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.color(\.muted))
                            .padding(.horizontal, 10)
                    }
                    ForEach(model.projects) { progress in
                        projectRow(progress)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            folderLine
        }
        .background(theme.color(\.side))
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
    }

    private func row(_ domain: AppModel.Domain, _ title: String, systemImage: String,
                     tint: KeyPath<Theme, NSColor>, count: Int?) -> some View {
        SidebarRow(selected: model.domain == domain, height: 32, count: count) {
            model.domain = domain
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(theme.color(tint))
                .frame(width: 16)
        } label: {
            Text(title)
        }
    }

    private func projectRow(_ progress: ProjectProgress) -> some View {
        let path = progress.project.path
        return SidebarRow(selected: model.domain == .project(path), height: 30, count: progress.open) {
            // Clicking the open project again goes from its page back to its tasks.
            if model.domain == .project(path), model.selection == path { model.selection = nil }
            model.domain = .project(path)
        } icon: {
            ProgressRing(fraction: progress.fraction)
                .foregroundStyle(theme.color(\.accent))
                .frame(width: 16)
        } label: {
            Text(progress.project.title)
        }
        .accessibilityValue("\(progress.done) of \(progress.total) tasks done")
    }

    private var folderLine: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isInICloud ? "icloud" : "folder")
                .foregroundStyle(theme.color(\.done))
            Text(model.folderDisplayName)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.color(\.muted))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .help(model.vault?.root.path(percentEncoded: false) ?? "")
    }
}

/// One selectable sidebar row: icon, label, optional count; selected rows sit on the surface colour.
private struct SidebarRow<Icon: View, Label: View>: View {
    let selected: Bool
    let height: CGFloat
    let count: Int?
    let action: () -> Void
    @ViewBuilder let icon: Icon
    @ViewBuilder let label: Label
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                label
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.color(\.muted))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 13, weight: selected ? .semibold : .medium))
            .foregroundStyle(theme.color(selected ? \.strong : \.fg))
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(selected ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A ring with a pie inside that fills clockwise from the top: done/total of a project's tasks.
struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 1.4)
            Pie(fraction: fraction)
        }
        .frame(width: 12, height: 12)
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }

    nonisolated private struct Pie: Shape {
        let fraction: Double

        func path(in rect: CGRect) -> Path {
            guard fraction > 0 else { return Path() }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            var path = Path()
            path.move(to: center)
            path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                        startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * min(fraction, 1)), clockwise: false)
            path.closeSubpath()
            return path
        }
    }
}
