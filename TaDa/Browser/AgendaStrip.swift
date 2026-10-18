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
    private static let rowHeight: CGFloat = 38
    private static let rowSpacing: CGFloat = 2

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
                pages
            }
        }
        .clipped()
        .background(AgendaSwipeCatcher(monthOpen: model.agendaMonthOpen, onSwipe: swipe))
    }

    private func swipe(_ swipe: AgendaSwipe) {
        DispatchQueue.main.async { withAnimation(AgendaMotion.spring) { model.agendaMonthOpen = swipe == .openMonth } }
    }

    /// What a ScrollView of pages is rebuilt for: its kind and its width.
    private struct ShownPages: Hashable {
        let open: Bool
        let width: CGFloat
    }

    /// The week, or with the month open the months, as pages that scroll sideways and settle a page at a time. The strip is
    /// as tall as the settled page's rows.
    private var pages: some View {
        let open = model.agendaMonthOpen
        let rows = open ? model.agendaAnchor.isoWeeksOfMonth.count : 1
        let marks = model.agendaMarks
        return GeometryReader { proxy in ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                if open {
                    ForEach(AgendaPaging.months(today: model.today), id: \.self) { key in
                        let month = AgendaPaging.monthStart(forKey: key)
                        VStack(spacing: Self.rowSpacing) {
                            ForEach(month.isoWeeksOfMonth, id: \.self) { weekRow($0, month: month, marks: marks) }
                        }
                        .frame(width: proxy.size.width)
                    }
                } else {
                    ForEach(AgendaPaging.weeks(today: model.today), id: \.self) { key in
                        weekRow(AgendaPaging.week(forKey: key), month: model.agendaAnchor, marks: marks).frame(width: proxy.size.width)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: Binding<Int?> {
            open ? AgendaPaging.monthKey(of: model.agendaSelection) : AgendaPaging.weekKey(of: model.agendaSelection)
        } set: { key in
            guard let key else { return }
            let selection = model.agendaSelection
            if open, key != AgendaPaging.monthKey(of: selection) {
                model.agendaSelection = AgendaPaging.selection(movingToMonth: key, from: selection)
            } else if !open, key != AgendaPaging.weekKey(of: selection) {
                model.agendaSelection = AgendaPaging.selection(movingToWeek: key, from: selection)
            }
        })
        .id(ShownPages(open: open, width: proxy.size.width)) }
        .frame(height: CGFloat(rows) * Self.rowHeight + CGFloat(rows - 1) * Self.rowSpacing)
        .animation(AgendaMotion.spring, value: rows)
    }

    private func weekRow(_ week: ISOWeek, month: LocalDate, marks: [LocalDate: DayMarks]) -> some View {
        HStack(spacing: 0) {
            weekCell(week).frame(width: Self.weekColumn)
            ForEach(week.days, id: \.self) { dayCell($0, month: month, marks: marks).frame(maxWidth: .infinity) }
        }
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
            stepButton("chevron.left", label: "Previous \(unit)") { withAnimation(AgendaMotion.spring) { model.stepAgenda(by: -1) } }
            Rectangle().fill(theme.color(\.border)).frame(width: 1)
            Button { withAnimation(AgendaMotion.spring) { model.showAgendaToday() } } label: {
                Text("Today").font(.system(size: 12)).foregroundStyle(theme.color(\.fg)).padding(.horizontal, 8)
                    .frame(maxHeight: .infinity).contentShape(.rect)
            }
            .buttonStyle(.plain)
            Rectangle().fill(theme.color(\.border)).frame(width: 1)
            stepButton("chevron.right", label: "Next \(unit)") { withAnimation(AgendaMotion.spring) { model.stepAgenda(by: 1) } }
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
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .top)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week \(week.week)\(hasNote ? ", note" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayCell(_ day: LocalDate, month: LocalDate, marks: [LocalDate: DayMarks]) -> some View {
        let selected = model.agendaSelection == .day(day)
        let isToday = day == model.today
        let faded = day.month != month.month || day < model.today
        return Button { model.agendaSelection = .day(day) } label: {
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .font(.system(size: 13, weight: selected || isToday ? .bold : .medium))
                    .foregroundStyle(theme.color(selected ? \.bg : isToday ? \.accent : faded ? \.muted : \.fg))
                    .frame(width: 24, height: 22)
                    .background(selected ? theme.color(isToday ? \.accent : \.strong) : .clear, in: .rect(cornerRadius: 11))
                AgendaDots(model: model, day: day, size: 4, marks: marks[day])
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel((isToday ? "Today, " : "") + day.formatted(.weekdayDayMonth) + AgendaDots.spoken(model, day, marks: marks[day]))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Reports a vertical trackpad swipe over its frame: one per gesture, from the scroll phases, and none for momentum. A mouse
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
