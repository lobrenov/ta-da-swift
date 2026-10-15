// The iPhone's Group menu on a list's title line, its tag filter (the pill, the picked tags' chips and Clear, and the
// sheet the pill opens), and a Status, Date or Open list's foldable sections.
#if os(iOS)
import SwiftUI
import TaDaCore

/// The list's grouping in a capsule; a tap opens the Group by menu, its default marked.
struct PhoneGroupMenu: View {
    let model: AppModel
    let list: GroupedList
    @Environment(\.theme) private var theme

    var body: some View {
        let grouping = model.grouping(of: list)
        Menu {
            Picker("Group by", selection: Binding(get: { model.grouping(of: list) },
                                                 set: { model.setGrouping($0, of: list) })) {
                ForEach(list.groupings, id: \.self) { choice in
                    if choice == list.defaultGrouping {
                        Label { Text(choice.rawValue); Text("Default") } icon: { Image(systemName: choice.systemImage) }
                            .tag(choice)
                    } else {
                        Label(choice.rawValue, systemImage: choice.systemImage).tag(choice)
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text(grouping.rawValue).foregroundStyle(theme.color(\.fg))
                Image(systemName: "chevron.up.chevron.down")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(theme.color(\.muted))
            }
            .scaledFont(size: 15)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .scaledMinHeight(32)
            .background(theme.color(\.code), in: .capsule)
            .overlay(Capsule().strokeBorder(theme.color(\.border)))
            .contentShape(.capsule)
        }
        .accessibilityLabel("Group by \(grouping.rawValue)")
    }
}

/// The filter pill, then the picked tags as chips with ×, then Clear. Nothing when no file in `items` carries a tag
/// and none is picked.
struct PhoneTagFilterBar: View {
    let model: AppModel
    let domain: AppModel.Domain
    /// The page's files before filtering.
    let items: [Item]
    @State private var isPicking = false
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let filter = model.tagFilter(on: domain)
        if filter.isActive || items.contains(where: { !$0.tags.isEmpty }) {
            WrappingHStack(spacing: 8) {
                Button { isPicking = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .scaledFont(size: 12, weight: .bold)
                            .foregroundStyle(filter.isActive ? theme.color(\.accent) : theme.color(\.muted))
                        Text("Filter")
                        if filter.picked.count > 1 {
                            Text("\(filter.picked.count)")
                                .scaledFont(size: 12, weight: .bold)
                                .monospacedDigit()
                                .foregroundStyle(theme.color(\.bg))
                                .padding(.horizontal, 6)
                                .background(theme.color(\.accent), in: .capsule)
                        }
                    }
                    .foregroundStyle(theme.color(filter.isActive ? \.strong : \.muted))
                    .padding(.leading, 11)
                    .padding(.trailing, 13)
                    .scaledMinHeight(32)
                    .background(filter.isActive ? theme.tagFill() : .clear, in: .capsule)
                    .overlay {
                        if filter.isActive {
                            Capsule().strokeBorder(theme.tagRing)
                        } else {
                            Capsule().strokeBorder(theme.color(\.surface), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(filter.isActive ? "Filter, \(filter.picked.count) tags picked" : "Filter by tag")
                let tags = TagFilter.tags(of: items)
                ForEach(filter.picked.sorted(), id: \.self) { path in
                    if let tag = tags.first(where: { $0.tag.path == path })?.tag ?? Tag(path) {
                        HStack(spacing: 6) {
                            Image(systemName: "tag").scaledFont(size: 12, weight: .semibold).foregroundStyle(theme.color(\.accent))
                            TagName(tag: tag).foregroundStyle(theme.color(\.strong)).lineLimit(1)
                            Button {
                                nav.play(.pick)
                                model.toggleFilterTag(path, on: domain)
                            } label: {
                                Image(systemName: "xmark")
                                    .scaledFont(size: 11, weight: .bold)
                                    .foregroundStyle(theme.color(\.muted))
                                    .frame(width: 28, height: 28)
                                    .contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop filtering by \(tag.name)")
                        }
                        .padding(.leading, 11)
                        .padding(.trailing, 2)
                        .scaledMinHeight(32)
                        .background(theme.tagFill(), in: .capsule)
                        .overlay(Capsule().strokeBorder(theme.tagRing))
                    }
                }
                if filter.isActive {
                    Button("Clear") { model.clearTagFilter(on: domain) }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.color(\.accent))
                        .scaledMinHeight(32)
                        .padding(.horizontal, 4)
                }
            }
            .scaledFont(size: 15)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .sheet(isPresented: $isPicking) { PhoneTagFilterSheet(model: model, domain: domain, items: items) }
        }
    }
}

/// The page's tags with counts, ticked when picked; a tap picks or unpicks one and the sheet stays.
struct PhoneTagFilterSheet: View {
    let model: AppModel
    let domain: AppModel.Domain
    let items: [Item]
    @State private var query = ""
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        let filter = model.tagFilter(on: domain)
        let shown = filter.apply(items).count
        NavigationStack {
            List {
                let menu = FilterTagChoice.menu(items: items, picked: filter.picked, query: query, keeping: nil)
                Section {
                    ForEach(menu.sections.flatMap(\.items), id: \.tag.path) { row($0) }
                } header: {
                    Text("Tags in this view")
                } footer: {
                    Text("Shows files with any picked tag. \(shown) of \(items.count) shown.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color(\.bg))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tags")
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { model.clearTagFilter(on: domain) }
                        .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(theme.color(\.accent))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ choice: FilterTagChoice) -> some View {
        Button {
            nav.play(.pick)
            model.toggleFilterTag(choice.tag.path, on: domain)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tag").foregroundStyle(theme.color(\.accent))
                TagName(tag: choice.tag).foregroundStyle(theme.color(\.fg)).lineLimit(1)
                Spacer()
                Text("\(choice.count)").foregroundStyle(theme.color(\.muted))
                Image(systemName: "checkmark")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(theme.color(\.accent))
                    .opacity(choice.isPicked ? 1 : 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(theme.color(\.code))
        .accessibilityValue(choice.accessibilityValue)
        .accessibilityAddTraits(choice.isPicked ? .isSelected : [])
    }
}

/// A Status, Date or Open list's sections, each foldable. `place` names a task's project or area on its row.
struct PhoneTaskSections: View {
    let model: AppModel
    let sections: [ListSection]
    let grouping: Grouping
    let foldKey: String
    let dates: TaskRow.Dates
    var place: ((Item) -> String)? = nil

    var body: some View {
        ForEach(sections) { section in
            let folded = model.isFolded(section, by: grouping, in: foldKey)
            PhoneFoldHeader(model: model, title: section.title, count: section.tasks.count,
                            group: section.foldName(grouping), in: foldKey, isFolded: folded)
            if !folded {
                ForEach(section.tasks) { task in
                    PhoneTaskRow(model: model, item: task, meta: place.map { .placedChips($0(task), dates) } ?? .chips(dates))
                }
            }
        }
    }
}
#endif
