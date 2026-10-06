// Beside the Source editor: where the file lives, what Ta Da read from it, where it shows up, and any problems.
import AppKit
import SwiftUI
import TaDaCore

struct FileInspector: View {
    let model: AppModel
    let document: OpenDocument
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("File") {
                    Text("\(model.folderDisplayName)/\(document.path)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(theme.color(\.fg))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    TimelineView(.everyMinute) { _ in
                        Text(fileFacts).font(.system(size: 12)).foregroundStyle(theme.color(\.muted))
                    }
                    Button("Reveal in Finder") {
                        if let url = model.vault?.url(for: document.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .padding(.top, 4)
                }
                Hairline()
                section("Parsed as") {
                    if let item = document.item {
                        fact("Kind", "\(item.properties.kind.rawValue)  (type: \(item.properties.kind.rawValue))")
                        fact("Status", item.properties.status.rawValue)
                        let subtasks = item.subtasks
                        fact("Subtasks", subtasks.total == 0 ? "None" : "\(subtasks.done) of \(subtasks.total), from the checklist")
                        fact("Links out", item.links.isEmpty ? "None" : item.links.map { "[[\($0.target)]]" }.joined(separator: ", "))
                    } else {
                        Text("Not a Ta Da file: the frontmatter has no `type: task` or `type: project`, so Ta Da ignores it.")
                            .foregroundStyle(theme.color(\.fg))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let item = model.index[document.path] {
                    Hairline()
                    section("Appears in") {
                        let places = appearances(of: item)
                        if places.isEmpty {
                            Text("No list: done and not completed today.").foregroundStyle(theme.color(\.muted))
                        }
                        ForEach(places, id: \.title) { place in
                            HStack(spacing: 8) {
                                Image(systemName: place.systemImage)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.color(place.tint))
                                    .frame(width: 16)
                                    .accessibilityHidden(true)
                                Text(place.title).foregroundStyle(theme.color(\.fg))
                                Spacer(minLength: 8)
                                Text(place.reason).font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted))
                            }
                        }
                    }
                    let warnings = model.index.warnings(for: item)
                    if !warnings.isEmpty {
                        Hairline()
                        section("Warnings") { WarningList(warnings: warnings) }
                    }
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(theme.color(\.side))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File inspector")
    }

    private var fileFacts: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(document.text.utf8.count), countStyle: .file)
        let modified = document.modified.map { " · modified \($0.formatted(.relative(presentation: .named)))" } ?? ""
        return "\(size) · UTF-8\(modified)"
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.66)
                .foregroundStyle(theme.color(\.muted))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted))
            Text(value).foregroundStyle(theme.color(\.fg)).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private struct Place {
        var title: String
        var reason: String
        var systemImage: String
        var tint: KeyPath<Theme, NSColor>
    }

    /// The sidebar lists this file shows in, and why.
    private func appearances(of item: Item) -> [Place] {
        let index = model.index, today = model.today, p = item.properties
        guard p.kind == .task else {
            return p.status == .done ? [] : [Place(title: "Projects", reason: "not done", systemImage: "circle.dotted", tint: \.accent)]
        }
        var places: [Place] = []
        if index.isInToday(item, today: today) {
            let reason = p.status == .done ? "completed today"
                : index.isOverdue(item, today: today) ? "overdue"
                : p.dueDate.map { $0 <= today } == true ? "dueDate" : "deadline"
            places.append(Place(title: "Today", reason: reason, systemImage: "star.fill", tint: \.due))
        }
        for entry in index.upcomingEntries(of: item, after: today) {
            places.append(Place(title: "Upcoming · \(entry.date.formatted(.weekdayDayMonth))",
                                reason: entry.kind == .due ? "dueDate" : "deadline", systemImage: "calendar", tint: \.deadline))
        }
        if let project = index.project(of: item) {
            places.append(Place(title: project.title, reason: "project", systemImage: "circle.dotted", tint: \.accent))
        } else if index.isLoose(item) {
            places.append(Place(title: "Loose tasks", reason: "no project", systemImage: "tray", tint: \.accent))
        }
        return places
    }
}
