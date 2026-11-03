// The iPhone's Group by and Filter… for a list's ⋯ menu, the picked tags' chips over the list, the sheet Filter… opens,
// and a Status, Date or Open list's foldable sections.
#if os(iOS)
import SwiftUI
import TaDaCore

/// The Group by picker, its default marked, for a menu.
struct PhoneGroupPicker: View {
    let model: AppModel
    let list: GroupedList

    var body: some View {
        Picker("Group by", systemImage: model.grouping(of: list).systemImage,
               selection: Binding(get: { model.grouping(of: list) }, set: { model.setGrouping($0, of: list) })) {
            ForEach(list.groupings, id: \.self) { choice in
                if choice == list.defaultGrouping {
                    Label { Text(choice.rawValue); Text("Default") } icon: { Image(systemName: choice.systemImage) }
                        .tag(choice)
                } else {
                    Label(choice.rawValue, systemImage: choice.systemImage).tag(choice)
                }
            }
        }
    }
}

/// A list's ⋯ menu items: Group by `group`'s picker, then Filter…, which sets `isFiltering`. Filter… shows while a file in
/// `items` carries a tag or one is picked.
struct PhoneGroupFilterItems: View {
    let model: AppModel
    var group: GroupedList? = nil
    let domain: AppModel.Domain
    let items: [Item]
    @Binding var isFiltering: Bool

    var body: some View {
        if let group { PhoneGroupPicker(model: model, list: group).pickerStyle(.menu) }
        if model.tagFilter(on: domain).isActive || items.contains(where: { !$0.tags.isEmpty }) {
            Button("Filter…", systemImage: "line.3.horizontal.decrease") { isFiltering = true }
        }
    }
}

/// While tags are picked: each as a chip with ×, how many of `items` are shown, and Clear.
struct PhoneTagFilterBar: View {
    let model: AppModel
    let domain: AppModel.Domain
    /// The page's files before filtering.
    let items: [Item]
    /// How many of them the filter leaves.
    let shown: Int
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let filter = model.tagFilter(on: domain)
        if filter.isActive {
            WrappingHStack(spacing: 8) {
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
                                    .frame(width: 44, height: 44)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop filtering by \(tag.name)")
                        }
                        .padding(.leading, 11)
                        .padding(.trailing, -6)
                        .frame(height: 32)
                        .background(theme.tagFill(), in: .capsule)
                        .overlay(Capsule().strokeBorder(theme.tagRing))
                        .padding(.trailing, 8)
                    }
                }
                Text("\(shown) of \(items.count) shown")
                    .scaledFont(size: 13)
                    .foregroundStyle(theme.color(\.muted))
                    .frame(minHeight: 44)
                Button("Clear") { model.clearTagFilter(on: domain) }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.color(\.accent))
                    .padding(.horizontal, 4)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .scaledFont(size: 15)
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
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
                    Text("\(shown) of \(items.count) shown")
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
    var place: ((Item) -> String?)? = nil

    var body: some View {
        ForEach(sections) { section in
            let folded = model.isFolded(section, by: grouping, in: foldKey)
            PhoneFoldHeader(model: model, title: section.title, count: section.tasks.count,
                            group: section.foldName(grouping), in: foldKey, isFolded: folded, quiet: section.isClosed)
            if !folded {
                ForEach(section.tasks) { task in
                    PhoneTaskRow(model: model, item: task, meta: .row(dates, place: place?(task)))
                }
            }
        }
    }
}
#endif
