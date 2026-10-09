// The iPhone's root once a folder is open: five tabs, each a navigation stack, with the date, move and area sheets
// over them, and the question deleting an area asks.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneRootView: View {
    let model: AppModel
    @State private var nav = PhoneNavigation()
    @Environment(\.theme) private var theme

    var body: some View {
        TabView(selection: $nav.tab) {
            Tab("Today", systemImage: "star.fill", value: PhoneTab.today) {
                stack(.today) { PhoneTaskListScreen(model: model, kind: .today) }
            }
            Tab("Upcoming", systemImage: "calendar", value: PhoneTab.upcoming) {
                stack(.upcoming) { PhoneUpcomingScreen(model: model) }
            }
            Tab("Loose", systemImage: "tray", value: PhoneTab.loose) {
                stack(.loose) { PhoneTaskListScreen(model: model, kind: .loose) }
            }
            Tab("Projects", systemImage: "chart.pie", value: PhoneTab.projects) {
                stack(.projects) { PhoneProjectsScreen(model: model) }
            }
            Tab("Other", systemImage: "ellipsis.circle", value: PhoneTab.other) {
                stack(.other) { PhoneOtherScreen(model: model) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(theme.color(\.accent))
        .sheet(item: $nav.sheet) { sheet in
            switch sheet {
            case let .date(kind, paths): PhoneDateSheet(model: model, kind: kind, paths: paths)
            case let .move(paths): PhoneMoveSheet(model: model, kind: .move, paths: paths)
            case let .area(paths): PhoneMoveSheet(model: model, kind: .area, paths: paths)
            }
        }
        .alert(trashTitle, isPresented: Binding { model.trashConfirmation != nil } set: { if !$0 { model.trashConfirmation = nil } },
               presenting: model.trashConfirmation) { request in
            Button("Move \(request.count == 1 ? "1 File" : "\(request.count) Files") to Trash", role: .destructive) {
                nav.play(.trash)
                Task {
                    await model.confirmTrash(request)
                    nav.dropScreens { model.index[$0] == nil }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(TrashConfirmationText(model: model).message)
        }
        .environment(nav)
        .phoneHaptics(nav, enabled: model.haptics)
        .onChange(of: nav.tab) { nav.endPicking() }
    }

    /// "Move “Personal” to Trash?", or the number of files.
    private var trashTitle: String {
        let items = model.trashConfirmation?.paths.compactMap { model.index[$0] } ?? []
        return items.count == 1 ? "Move “\(items[0].title)” to Trash?" : "Move \(items.count) Files to Trash?"
    }

    private func stack(_ tab: PhoneTab, @ViewBuilder root: () -> some View) -> some View {
        PhoneSearchStack {
            NavigationStack(path: nav.stack(tab)) {
                root().navigationDestination(for: PhoneRoute.self) { route in
                    switch route {
                    case let .file(path): PhoneFileScreen(model: model, path: path)
                    case let .project(path): PhoneProjectScreen(model: model, path: path)
                    case let .area(path): PhoneAreaScreen(model: model, path: path)
                    case let .settings(section): PhoneSettingsScreen(model: model, section: section)
                    case .trash: PhoneTrashScreen(model: model)
                    }
                }
            }
        }
    }
}
#endif
