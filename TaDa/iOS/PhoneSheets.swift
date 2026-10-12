// The sheets that set a property on one or more files: a due date or deadline from a month calendar, or a project or
// area. Each sets nothing until ✓.
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
        _kind = State(initialValue: kind)
        _days = State(initialValue: [.due: due, .deadline: deadline])
        _month = State(initialValue: ((kind == .due ? due : deadline) ?? model.today).startOfMonth)
    }

    private var day: LocalDate? { days[kind] ?? nil }

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
                    if day != nil {
                        Button("Clear \(kind == .due ? "Due Date" : "Deadline")", role: .destructive) { set(nil) }
                            .scaledFont(size: 17)
                            .foregroundStyle(theme.color(\.deadline))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(theme.color(\.bg))
            .navigationTitle(kind.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { apply() }
                        .tint(theme.color(\.accent))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: kind) { month = (day ?? model.today).startOfMonth }
    }

    private var quickDays: some View {
        let today = model.today
        let choices: [(String, String, LocalDate)] = [
            ("Today", "star.fill", today),
            ("Tomorrow", "sun.max", today.adding(days: 1)),
            ("This Weekend", "sofa", CalendarPickerModel.thisWeekend(after: today)),
            ("Next Week", "arrow.right.circle", CalendarPickerModel.nextWeek(after: today)),
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
        let grid = MonthGrid(month)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7)
        let other = days[kind == .due ? .deadline : .due] ?? nil
        return VStack(spacing: 10) {
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
                        dayCell(date, other: other)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        // Seven columns of fixed-size day circles: past this, the numbers wouldn't fit.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func dayCell(_ date: LocalDate, other: LocalDate?) -> some View {
        let isSet = date == day
        let isToday = date == model.today
        return Button { set(date) } label: {
            VStack(spacing: 2) {
                Text("\(date.day)")
                    .scaledFont(size: 19, weight: isSet || isToday ? .bold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(isSet ? theme.color(\.bg) : theme.color(isToday ? \.accent : date < model.today ? \.muted : \.fg))
                    .frame(width: 38, height: 38)
                    .background(isSet ? theme.color(kind.tint) : .clear, in: .circle)
                Circle()
                    .fill(date == other ? theme.color(kind == .due ? \.deadline : \.due) : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.weekdayDayMonth) + (isToday ? ", today" : ""))
        .accessibilityAddTraits(isSet ? .isSelected : [])
    }

    private func set(_ date: LocalDate?) {
        days[kind] = .some(date)
        changed.insert(kind)
        if let date { month = date.startOfMonth }
        nav.play(.pick)
    }

    private func apply() {
        let changes = AgendaEntry.Kind.changes(changed, in: days)
        let paths = paths
        nav.endPicking()
        dismiss()
        Task {
            for (kind, date) in changes {
                await model.setDate(kind, to: date, of: paths)
            }
        }
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
