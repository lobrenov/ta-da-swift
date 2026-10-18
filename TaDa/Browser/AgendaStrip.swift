// The Agenda's header: its title with Week | Month and ‹ Today ›, then the days of the selected week, or every week of
// the month when it's open, each row led by its ISO week number. A day shows its dots: a ring when its daily note has
// unchecked boxes, `due` when an open task is due or at its deadline, `muted` for an event or reminder.
#if os(macOS)
import SwiftUI
import TaDaCore

struct AgendaStrip: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    private static let weekColumn: CGFloat = 40

    /// Which way the grid last slid; the slide is set before the step so the grid leaving uses it too.
    private enum Slide { case none, next, previous }
    @State private var slide = Slide.none

    private var slideTransition: AnyTransition {
        switch slide {
        case .none: .opacity
        case .next: .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .previous: .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        }
    }

    private var weeks: [ISOWeek] {
        let range = model.agendaRange
        return (0..<(range.lowerBound.days(to: range.upperBound) + 1) / 7).map { range.lowerBound.adding(days: $0 * 7).isoWeek }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Too narrow for the title and both controls, the title gives way and the icon stays.
            ViewThatFits(in: .horizontal) {
                DomainHeader(.agenda) { controls }
                HStack {
                    Image(systemName: AppModel.Domain.agenda.systemImage).font(.system(size: 20))
                        .foregroundStyle(theme.color(AppModel.Domain.agenda.tint)).accessibilityLabel("Agenda")
                    Spacer(minLength: 8)
                    controls
                }
            }
            if model.agendaMonthOpen {
                Text(model.agendaAnchor.formatted(.monthYear)).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.color(\.strong))
            }
            VStack(spacing: 2) {
                initials
                ForEach(weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        weekCell(week).frame(width: Self.weekColumn)
                        ForEach(week.days, id: \.self) { dayCell($0).frame(maxWidth: .infinity) }
                    }
                }
            }
            .id(ShownPeriod(first: model.agendaRange.lowerBound, monthOpen: model.agendaMonthOpen))
            .transition(slideTransition)
        }
        .clipped()
        .background(AgendaSwipeCatcher(monthOpen: model.agendaMonthOpen, onSwipe: swipe))
    }

    private struct ShownPeriod: Hashable {
        let first: LocalDate
        let monthOpen: Bool
    }

    private func swipe(_ swipe: AgendaSwipe) {
        let apply: () -> Void
        switch swipe {
        case let .step(steps):
            slide = steps > 0 ? .next : .previous
            apply = { model.agendaSelection = AgendaPaging.selection(stepping: steps, byMonth: model.agendaMonthOpen, from: model.agendaSelection) }
        case .openMonth, .closeMonth:
            slide = .none
            apply = { model.agendaMonthOpen = swipe == .openMonth }
        }
        DispatchQueue.main.async { withAnimation(AgendaMotion.spring, apply) }
    }

    private var initials: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return HStack(spacing: 0) {
            Text("W").frame(width: Self.weekColumn)
            ForEach(1...7, id: \.self) { Text(symbols[$0 % 7]).frame(maxWidth: .infinity) }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(theme.color(\.muted))
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            SegmentedControl(label: "Calendar size", options: [(false, "Week"), (true, "Month")],
                             selection: Binding { model.agendaMonthOpen } set: { model.agendaMonthOpen = $0 },
                             height: 22, unselectedWeight: .semibold)
            stepper
        }
    }

    /// ‹ Today ›, which step a day, or a week when a week is picked.
    private var stepper: some View {
        let unit: String = if case .week = model.agendaSelection { "week" } else { "day" }
        return HStack(spacing: 0) {
            stepButton("chevron.left", label: "Previous \(unit)") { model.stepAgenda(by: -1) }
            Rectangle().fill(theme.color(\.border)).frame(width: 1)
            Button { model.showAgendaToday() } label: {
                Text("Today").font(.system(size: 12)).foregroundStyle(theme.color(\.fg)).padding(.horizontal, 8)
                    .frame(maxHeight: .infinity).contentShape(.rect)
            }
            .buttonStyle(.plain)
            Rectangle().fill(theme.color(\.border)).frame(width: 1)
            stepButton("chevron.right", label: "Next \(unit)") { model.stepAgenda(by: 1) }
        }
        .frame(height: 26)
        .background(theme.color(\.code), in: .rect(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Move through days")
    }

    private func stepButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 10, weight: .bold)).foregroundStyle(theme.color(\.fg))
                .frame(width: 26).frame(maxHeight: .infinity).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func weekCell(_ week: ISOWeek) -> some View {
        let selected = model.agendaSelection == .week(week)
        let hasNote = model.index.weekNote(for: week, names: model.dailyNoteNames) != nil
        return Button { model.agendaSelection = .week(week) } label: {
            Text("\(week.week)")
                .font(.system(size: 11, weight: selected ? .bold : .semibold, design: .monospaced))
                .foregroundStyle(theme.color(selected ? \.bg : hasNote ? \.link : \.muted))
                .frame(width: 24, height: 22)
                .background(selected ? theme.color(\.strong) : .clear, in: .rect(cornerRadius: 11))
                .padding(.top, 4)
                .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .top)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week \(week.week)\(hasNote ? ", note" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayCell(_ day: LocalDate) -> some View {
        let selected = model.agendaSelection == .day(day)
        let isToday = day == model.today
        let faded = day.month != model.agendaAnchor.month || day < model.today
        return Button { model.agendaSelection = .day(day) } label: {
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .font(.system(size: 13, weight: selected || isToday ? .bold : .medium))
                    .foregroundStyle(theme.color(selected ? \.bg : isToday ? \.accent : faded ? \.muted : \.fg))
                    .frame(width: 24, height: 22)
                    .background(selected ? theme.color(isToday ? \.accent : \.strong) : .clear, in: .rect(cornerRadius: 11))
                AgendaDots(model: model, day: day, size: 4)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel((isToday ? "Today, " : "") + day.formatted(.weekdayDayMonth) + AgendaDots.spoken(model, day))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Reports a trackpad swipe over its frame: one per gesture, from the scroll phases, and none for momentum. A mouse
/// wheel has no phases and is ignored.
private struct AgendaSwipeCatcher: NSViewRepresentable {
    let monthOpen: Bool
    let onSwipe: (AgendaSwipe) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.monthOpen = monthOpen
        view.onSwipe = onSwipe
    }

    final class CatcherView: NSView {
        var monthOpen = false
        var onSwipe: (AgendaSwipe) -> Void = { _ in }
        private var tracker = AgendaSwipeTracker()
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = window == nil ? nil : NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.scrolled(event)
                return event
            }
        }

        isolated deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        private func scrolled(_ event: NSEvent) {
            guard event.window === window, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) { tracker.reset() }
            guard event.momentumPhase.isEmpty, event.phase.contains(.changed) || event.phase.contains(.began) else {
                if event.phase.contains(.ended) || event.phase.contains(.cancelled) { tracker.reset() }
                return
            }
            let sign = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
            if let swipe = tracker.add(dx: event.scrollingDeltaX * sign, dy: event.scrollingDeltaY * sign, monthOpen: monthOpen) {
                onSwipe(swipe)
            }
        }
    }
}
#endif
