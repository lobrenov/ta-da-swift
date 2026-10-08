// The iPhone's root once a folder is open: five tabs, each a navigation stack, with the date and project sheets
// over them.
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
            case let .project(paths): PhoneProjectSheet(model: model, paths: paths)
            }
        }
        .environment(nav)
        .phoneHaptics(nav, enabled: model.haptics)
        .onChange(of: nav.tab) { nav.endPicking() }
    }

    private func stack(_ tab: PhoneTab, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: nav.stack(tab)) {
            root().navigationDestination(for: PhoneRoute.self) { route in
                switch route {
                case let .file(path): PhoneFileScreen(model: model, path: path)
                case let .project(path): PhoneProjectScreen(model: model, path: path)
                case let .settings(section): PhoneSettingsScreen(model: model, section: section)
                case .trash: PhoneTrashScreen(model: model)
                }
            }
        }
    }
}
#endif
