// Root view: the folder picker until a folder is open, then sidebar + workspace. Applies the theme.
import AppKit
import Combine
import SwiftUI
import TaDaCore

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.state {
            case .noFolder, .failed:
                FolderPickerView(model: model)
            case .loading, .ready:
                NavigationSplitView {
                    SidebarView(model: model)
                } detail: {
                    WorkspaceView(model: model)
                }
            }
        }
        .environment(\.theme, model.theme)
        // No toolbar fill: each column's own colour runs up under the toolbar (proven in the M1 spike).
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .containerBackground(model.theme.color(\.bg), for: .window)
        .frame(minWidth: 900, minHeight: 480)
        .alert("Couldn’t save", isPresented: Binding { model.errorMessage != nil } set: { if !$0 { model.errorMessage = nil } }) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.start() }
        .onChange(of: model.themeName, initial: true) {
            // Light themes use the light system appearance so menus, pickers and scroll bars match.
            NSApp.appearance = NSAppearance(named: model.theme.isDark ? .darkAqua : .aqua)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            model.today = LocalDate(Date())
        }
    }
}

#Preview {
    ContentView(model: AppModel())
}
