// The sheets that set a property on one or more files: a due date or deadline from a month calendar, or a project or
// area. Each sets nothing until ✓; swiping the date sheet down sets its dates too. A task's due date sheet also holds its
// repeat rule, on a Repeat page.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneDateSheet: View {
    let model: AppModel
    let paths: [String]
    @State private var kind: AgendaEntry.Kind
    /// The day each kind will be set to; nil clears it. Starts from the day the files agree on.
    @State private var days: [AgendaEntry.Kind: LocalDate?]
    /// The kinds the user set or cleared here; only these are written.
    @State private var changed: Set<AgendaEntry.Kind> = []
    @State private var month: LocalDate
    /// The Repeat page's model, and the rule the files share (nil when they have none or differ).
    @State private var picker = CalendarPickerModel()
    private let sharedRule: RepeatRule?
    /// The rule set or stopped on the Repeat page, written with the dates; nil while it's untouched.
    @State private var repeatChange: RepeatRule??
    @State private var showsRepeat = false
    /// ✕ or ✓ closed the sheet; else it was swiped down, which sets what's staged.
    @State private var isClosed = false
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    init(model: AppModel, kind: AgendaEntry.Kind, paths: [String]) {
        self.model = model
        self.paths = paths
        let items = paths.compactMap { model.index[$0] }
        func agreed(_ date: KeyPath<Properties, LocalDate?>) -> LocalDate? {
            let dates = Set(items.map { $0.properties[keyPath: date] })
            return dates.count == 1 ? dates.first ?? nil : nil
        }
        let due = agreed(\.dueDate), deadline = agreed(\.deadline)
        sharedRule = CalendarPickerModel.Repeating.sharedRule(of: items)
        _kind = State(initialValue: kind)
        _days = State(initialValue: [.due: due, .deadline: deadline])
        _month = State(initialValue: ((kind == .due ? due : deadline) ?? model.today).startOfMonth)
    }

    private var day: LocalDate? { days[kind] ?? nil }

    /// Whether the files are all tasks, which can repeat.
    private var areTasks: Bool {
        let items = paths.compactMap { model.index[$0] }
        return !items.isEmpty && items.allSatisfy { $0.properties.kind == .task }
    }

    /// Whether the sheet has the Repeat row and page: the due date of tasks.
    private var isRepeatable: Bool { kind == .due && areTasks }

    /// The rule the files will have: the one set here, else the one they share.
    private var shownRule: RepeatRule? { repeatChange ?? sharedRule }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Date", selection: $kind) {
                        Label(AgendaEntry.Kind.due.name, systemImage: AgendaEntry.Kind.due.systemImage).tag(AgendaEntry.Kind.due)
                        Label(AgendaEntry.Kind.deadline.name, systemImage: AgendaEntry.Kind.deadline.systemImage).tag(AgendaEntry.Kind.deadline)
                    }
                    .pickerStyle(.segmented)
                    quickDays
                    calendar
                    if isRepeatable { repeatRow }
                    if day != nil {
                        Button("Clear \(kind == .due ? "Due Date" : "Deadline")", role: .destructive) { set(nil) }
                            .scaledFont(size: 17)
                            .foregroundStyle(theme.color(\.deadline))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(theme.color(\.bg))
            .navigationTitle(kind.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsRepeat) { PhoneRepeatPage(picker: picker) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        isClosed = true
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { apply() }
                        .tint(theme.color(\.accent))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { configureRepeat() }
        .onDisappear { if !isClosed, write() { nav.endPicking() } }
        .accessibilityAction(.escape) {
            isClosed = true
            dismiss()
        }
        .onChange(of: kind) {
            month = (day ?? model.today).startOfMonth
            configureRepeat()
        }
    }

    private var repeatRow: some View {
        Button { showsRepeat = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "repeat").foregroundStyle(theme.color(\.muted)).accessibilityHidden(true)
                Text("Repeat").foregroundStyle(theme.color(\.fg))
                Spacer()
                Text(shownRule?.frequencyLabel ?? "Never").foregroundStyle(theme.color(\.muted))
                Image(systemName: "chevron.right")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(theme.color(\.muted))
                    .accessibilityHidden(true)
            }
            .scaledFont(size: 17)
            .padding(.horizontal, 14)
            .scaledMinHeight(48)
            .background(theme.color(\.code), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(theme.color(\.border)) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Repeat")
        .accessibilityValue(shownRule?.frequencyLabel ?? "Never")
    }

    private var quickDays: some View {
        let today = model.today
        let choices: [(String, String, LocalDate)] = [
            ("Today", "star.fill", today),
            ("Tomorrow", "sun.max", today.adding(days: 1)),
            ("This Weekend", "sofa", today.thisWeekend),
            ("Next Week", "arrow.right.circle", today.nextWeek(firstWeekday: Calendar.current.firstWeekday)),
        ]
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(choices, id: \.0) { title, symbol, date in
                    Button { set(date) } label: {
                        Label(title, systemImage: symbol)
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(theme.color(day == date ? \.strong : \.fg))
                            .padding(.horizontal, 12)
                            .scaledMinHeight(34)
                            .background(theme.color(day == date ? \.surface : \.code), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(date.formatted(.weekdayDayMonth))
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var calendar: some View {
        PhoneMonthCalendar(month: $month, today: model.today, selected: day, tint: kind.tint,
                           other: days[kind == .due ? .deadline : .due] ?? nil, otherTint: kind == .due ? \.deadline : \.due,
                           occurrences: isRepeatable ? picker.occurrenceDays(in: month) : [], pick: set)
    }

    private func set(_ date: LocalDate?) {
        days[kind] = .some(date)
        changed.insert(kind)
        if let date { month = date.startOfMonth }
        configureRepeat()
        nav.play(.pick)
    }

    /// Gives the Repeat page the files as the dates here will leave them, and the rule they will have. Setting a rule, its
    /// end or When done, or stopping it, there holds the change until ✓.
    private func configureRepeat() {
        guard areTasks else { return }
        let items = stagedItems
        picker.today = model.today
        picker.firstWeekday = Calendar.current.firstWeekday
        picker.selected = days[.due] ?? nil
        picker.other = days[.deadline] ?? nil
        picker.cursor = picker.selected ?? model.today
        picker.configure(CalendarPickerModel.Repeating(items: items, index: model.index, rule: shownRule) { rule, _ in
            repeatChange = .some(rule)
            configureRepeat()
        })
    }

    private var stagedItems: [Item] {
        CalendarPickerModel.Repeating.staged(paths.compactMap { model.index[$0] }, days: days, changed: changed)
    }

    private func apply() {
        isClosed = true
        nav.endPicking()
        dismiss()
        write()
    }

    /// Writes the staged dates and rule, a rule still typed on the Repeat page included. False when nothing is staged.
    @discardableResult private func write() -> Bool {
        let typed = picker.isEnds ? nil : picker.typedRule
        let changes = AgendaEntry.Kind.changes(changed, in: days)
        let change = CalendarPickerModel.Repeating.held(typed.map { .some($0) } ?? repeatChange, staged: stagedItems)
        guard !changes.isEmpty || change != nil else { return false }
        let paths = paths
        Task {
            for (kind, date) in changes {
                await model.setDate(kind, to: date, of: paths)
            }
            if let change { await model.setRepeat(change, of: paths) }
        }
        return true
    }
}

/// A month of days: the one picked filled in `tint`, a coming occurrence on a faint `due` fill, and the file's `other`
/// date as a dot. A day `canPick` refuses is dimmed.
private struct PhoneMonthCalendar: View {
    @Binding var month: LocalDate
    let today: LocalDate
    let selected: LocalDate?
    let tint: KeyPath<Theme, PlatformColor>
    var other: LocalDate?
    var otherTint: KeyPath<Theme, PlatformColor> = \.deadline
    var occurrences: Set<LocalDate> = []
    var canPick: (LocalDate) -> Bool = { _ in true }
    let pick: (LocalDate) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let grid = MonthGrid(month)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7)
        VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.monthYear))
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(theme.color(\.strong))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { month = month.addingMonths(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                    .accessibilityLabel("Previous Month")
                Button { month = month.addingMonths(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                    .accessibilityLabel("Next Month")
            }
            .scaledFont(size: 17, weight: .semibold)
            .foregroundStyle(theme.color(\.accent))
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(grid.weekdaySymbols.indices, id: \.self) { i in
                    Text(grid.weekdaySymbols[i]).scaledFont(size: 13, weight: .semibold).foregroundStyle(theme.color(\.muted))
                }
                .accessibilityHidden(true)
                ForEach(grid.days.indices, id: \.self) { i in
                    if let date = grid.days[i] {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        // Seven columns of fixed-size day circles: past this, the numbers wouldn't fit.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func dayCell(_ date: LocalDate) -> some View {
        let isSet = date == selected
        let isToday = date == today
        let isOccurrence = occurrences.contains(date)
        return Button { pick(date) } label: {
            VStack(spacing: 2) {
                Text("\(date.day)")
                    .scaledFont(size: 19, weight: isSet || isToday ? .bold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(theme.color(isSet ? \.bg : isToday ? \.accent : isOccurrence ? \.strong : date < today ? \.muted : \.fg))
                    .frame(width: 38, height: 38)
                    .background(fill(isSet: isSet, isOccurrence: isOccurrence), in: .circle)
                Circle()
                    .fill(date == other ? theme.color(otherTint) : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canPick(date))
        .opacity(canPick(date) ? 1 : 0.4)
        .accessibilityLabel(date.formatted(.weekdayDayMonth) + (isToday ? ", today" : "") + (isOccurrence && !isSet ? ", repeats" : ""))
        .accessibilityAddTraits(isSet ? .isSelected : [])
    }

    private func fill(isSet: Bool, isOccurrence: Bool) -> Color {
        if isSet { return theme.color(tint) }
        return isOccurrence ? theme.color(\.due).opacity(theme.isDark ? 0.26 : 0.3) : .clear
    }
}

/// The Repeat page: the rule typed in a field and spelled out under it, When done, Ends and Stop Repeating. Each sets
/// its change on the date sheet, which writes it with ✓. Going back sets a typed rule that can start, and drops one that
/// can't.
private struct PhoneRepeatPage: View {
    let picker: CalendarPickerModel
    @State private var text = ""
    @State private var showsEnds = false
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "repeat").foregroundStyle(theme.color(\.muted))
                        TextField("", text: Binding { text } set: { text = $0; picker.phrase = $0 }, prompt: Text("every 2 weeks on mon"))
                            .foregroundStyle(theme.color(\.strong))
                            .focused($isFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { picker.confirm() }
                            .accessibilityLabel("Repeat rule")
                    }
                    .scaledFont(size: 17)
                    .padding(.horizontal, 14)
                    .scaledMinHeight(46)
                    .background(theme.color(\.code), in: .rect(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(theme.color(\.border)) }
                    if let rule = picker.displayedRule {
                        Text(picker.spelled(rule))
                            .scaledFont(size: 13)
                            .foregroundStyle(theme.color(picker.typedRule == nil ? \.strong : \.muted))
                            .padding(.horizontal, 14)
                    }
                    Text("Type repetition rules naturally. They're recognised as you type.")
                        .scaledFont(size: 13)
                        .foregroundStyle(theme.color(\.muted))
                        .padding(.horizontal, 14)
                }
                if let rule = picker.current {
                    VStack(spacing: 0) {
                        Toggle("When done", isOn: Binding { rule.whenDone } set: { picker.setWhenDone($0) })
                            .tint(theme.color(\.accent))
                            .padding(.horizontal, 14)
                            .scaledMinHeight(46)
                        Divider().overlay(theme.color(\.border))
                        Button {
                            picker.showEnds()
                            showsEnds = true
                        } label: {
                            HStack(spacing: 10) {
                                Text("Ends").foregroundStyle(theme.color(\.fg))
                                Spacer()
                                Text(rule.until?.formatted(.weekdayDayMonth) ?? "Never").foregroundStyle(theme.color(\.muted))
                                Image(systemName: "chevron.right")
                                    .scaledFont(size: 14, weight: .semibold)
                                    .foregroundStyle(theme.color(\.muted))
                            }
                            .padding(.horizontal, 14)
                            .scaledMinHeight(46)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ends")
                        .accessibilityValue(rule.until?.formatted(.weekdayDayMonthYear) ?? "Never")
                    }
                    .scaledFont(size: 17)
                    .background(theme.color(\.code), in: .rect(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(theme.color(\.border)) }
                    Button("Stop Repeating", role: .destructive) {
                        picker.stopRepeating()
                        dismiss()
                    }
                    .scaledFont(size: 17)
                    .foregroundStyle(theme.color(\.deadline))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.color(\.bg))
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsEnds) { PhoneRepeatEndsPage(picker: picker) }
        .onAppear {
            picker.phrase = ""
            text = picker.current?.phrase ?? ""
        }
        .onDisappear {
            guard !showsEnds else { return }
            if picker.typedRule != nil { picker.confirm() }
            picker.phrase = ""
        }
    }
}

/// The Ends page: a date page like the date sheet's, with Never, In 4 weeks and End of year. A day before the repeat
/// starts can't be picked.
private struct PhoneRepeatEndsPage: View {
    let picker: CalendarPickerModel
    @State private var month: LocalDate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    init(picker: CalendarPickerModel) {
        self.picker = picker
        _month = State(initialValue: picker.cursor.startOfMonth)
    }

    var body: some View {
        let today = picker.today
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(picker.endChoices, id: \.title) { title, date in
                            Button { end(on: date) } label: {
                                Text(title)
                                    .scaledFont(size: 15, weight: .semibold)
                                    .foregroundStyle(theme.color(picker.shownDate == date ? \.strong : \.fg))
                                    .padding(.horizontal, 12)
                                    .scaledMinHeight(34)
                                    .background(theme.color(picker.shownDate == date ? \.surface : \.code), in: .capsule)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .disabled(!picker.canPick(date))
                            .opacity(picker.canPick(date) ? 1 : 0.4)
                            .accessibilityValue(date?.formatted(.weekdayDayMonth) ?? "No end date")
                            .accessibilityAddTraits(picker.shownDate == date ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.never)
                PhoneMonthCalendar(month: $month, today: today, selected: picker.shownDate, tint: \.muted,
                                   occurrences: picker.occurrenceDays(in: month), canPick: { picker.canPick($0) }) { end(on: $0) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(theme.color(\.bg))
        .navigationTitle("Ends")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { picker.hideEnds() }
    }

    private func end(on day: LocalDate?) {
        guard picker.canPick(day) else { return }
        picker.setEnd(day)
        dismiss()
    }
}

/// The move sheet, which files tasks in a project or an area or makes them loose, or the area sheet, which files
/// projects in an area or takes them out of one. Either can create the area the files name, or a new project or area.
struct PhoneMoveSheet: View {
    enum Kind { case move, area }

    let model: AppModel
    let kind: Kind
    let paths: [String]
    /// The project or area picked, or `.some(nil)` for Loose tasks or No area; nil while nothing is picked.
    @State private var choice: Item??
    @State private var query = ""
    @State private var isNaming = false
    @State private var newName = ""
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    init(model: AppModel, kind: Kind, paths: [String]) {
        self.model = model
        self.kind = kind
        self.paths = paths
        _choice = State(initialValue: PhoneMoveRow.currentParent(index: model.index, files: paths.compactMap { model.index[$0] }))
    }

    var body: some View {
        let name = query.trimmingCharacters(in: .whitespaces)
        let files = paths.compactMap { model.index[$0] }
        let groups = kind == .move
            ? PhoneMoveRow.moveGroups(index: model.index, tasks: files, query: query)
            : PhoneMoveRow.areaGroups(index: model.index, projects: files, query: query)
        let noun = kind == .move ? "Project" : "Area"
        NavigationStack {
            List {
                ForEach(groups.indices, id: \.self) { i in
                    Section {
                        ForEach(groups[i]) { row($0) }
                    }
                }
                Section {
                    Button {
                        if name.isEmpty { isNaming = true } else { create(name) }
                    } label: {
                        Label(name.isEmpty ? "New \(noun)…" : "New \(noun) “\(name)”", systemImage: "plus")
                    }
                    .foregroundStyle(theme.color(\.accent))
                    .listRowBackground(theme.color(\.code))
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color(\.bg))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: kind == .move ? "Search projects and areas" : "Search areas")
            .navigationTitle(kind == .move ? "Move" : "Area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { apply() }
                        .disabled(choice == nil)
                        .tint(theme.color(\.accent))
                }
            }
            .alert("New \(noun)", isPresented: $isNaming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { create(newName.trimmingCharacters(in: .whitespaces)) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ row: PhoneMoveRow) -> some View {
        let isCurrent = switch row {
        case .none: choice == .some(nil)
        case let .project(progress): choice??.path == progress.project.path
        case let .area(area): choice??.path == area.path
        case .createArea: false
        }
        return Button {
            switch row {
            case .none: choice = .some(nil)
            case let .project(progress): choice = .some(progress.project)
            case let .area(area): choice = .some(area)
            case let .createArea(name): createArea(name)
            }
            nav.play(.pick)
        } label: {
            HStack(spacing: 12) {
                icon(row).frame(width: 22)
                Text(title(row))
                    .fontWeight(isArea(row) ? .semibold : .regular)
                    .foregroundStyle(theme.color(isArea(row) ? \.strong : \.fg))
                    .lineLimit(1)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(theme.color(\.accent))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(theme.color(\.code))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func title(_ row: PhoneMoveRow) -> String {
        switch row {
        case .none: kind == .move ? "Loose tasks" : "No area"
        case let .project(progress): progress.project.title
        case let .area(area): area.title
        case let .createArea(name): "Create Area “\(name)”"
        }
    }

    private func isArea(_ row: PhoneMoveRow) -> Bool { if case .area = row { true } else { false } }

    @ViewBuilder private func icon(_ row: PhoneMoveRow) -> some View {
        switch row {
        case .none:
            Image(systemName: kind == .move ? "tray" : "xmark").foregroundStyle(theme.color(kind == .move ? \.accent : \.muted))
        case let .project(progress):
            ProgressRing(progress).scaleEffect(20 / 14).foregroundStyle(theme.color(\.accent))
        case .area, .createArea:
            AreaIcon(size: 20)
        }
    }

    private func apply() {
        guard let choice else { return }
        let paths = paths
        nav.endPicking()
        dismiss()
        Task { await model.setParent(choice, of: paths) }
    }

    /// Creates the area the files name, which files them in it.
    private func createArea(_ name: String) {
        nav.endPicking()
        dismiss()
        Task { await model.newArea(named: name) }
    }

    private func create(_ name: String) {
        guard !name.isEmpty else { return }
        let paths = paths
        nav.play(.pick)
        nav.endPicking()
        dismiss()
        Task {
            switch kind {
            case .move: await model.newProject(named: name, linking: paths)
            case .area: await model.newArea(named: name, filing: paths)
            }
        }
    }
}
#endif
