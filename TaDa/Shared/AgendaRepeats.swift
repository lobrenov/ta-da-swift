// What the Mac's and the iPhone's Agenda share in a Repeats row: its pills, its place and its spoken label.
import SwiftUI
import TaDaCore

extension AppModel {
    /// The title of the project or area an occurrence's task sits in; nil for a loose task.
    func occurrencePlace(_ occurrence: Occurrence) -> String? {
        index.parent(of: occurrence.item)?.title
    }

    /// An occurrence row's spoken label: "Water plants, repeat, Repeats every week, Garden".
    func occurrenceLabel(_ occurrence: Occurrence, place: String?) -> String {
        ([occurrence.item.title, "repeat", RepeatWording.occurrenceHelp(occurrence, today: today)] + [place].compactMap { $0 })
            .joined(separator: ", ")
    }
}

/// An occurrence row's pills: "≈" for an estimate, "Deadline" for a deadline occurrence.
struct OccurrencePills: View {
    let occurrence: Occurrence
    @Environment(\.theme) private var theme

    var body: some View {
        if occurrence.estimated { pill("≈", tint: \.muted) }
        if occurrence.kind == .deadline { pill("Deadline", tint: \.deadline) }
    }

    private func pill(_ text: String, tint: KeyPath<Theme, PlatformColor>) -> some View {
        let label = Text(text)
        #if os(iOS)
        let sized = label.scaledFont(size: 15)
        #else
        let sized = label.font(.system(size: 12))
        #endif
        return sized
            .foregroundStyle(theme.color(\.muted))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(theme.color(tint).opacity(theme.isDark ? 0.2 : 0.12), in: .capsule)
            .fixedSize()
            .accessibilityHidden(true)
    }
}
