// Root view: the folder picker until a folder is open, then sidebar + workspace (on iOS, the Today list).
// Applies the theme.
import SwiftUI
import TaDaCore

#if os(macOS)
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
        .themed(by: model)
        // No toolbar fill: each column's own colour runs up under the toolbar (proven in the M1 spike).
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .containerBackground(model.theme.color(\.bg), for: .window)
        .frame(minWidth: 900, minHeight: 480)
        .alert("Ta Da", isPresented: Binding { model.errorMessage != nil } set: { if !$0 { model.errorMessage = nil } }) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.start() }
    }
}

#else
struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.state {
            case .noFolder, .failed:
                FolderPickerView(model: model)
            case .loading, .ready:
                NavigationStack {
                    List(model.todayTasks, id: \.path) { task in
                        Text(task.title)
                    }
                    .navigationTitle("Today")
                }
            }
        }
        .themed(by: model)
        .alert("Ta Da", isPresented: Binding { model.errorMessage != nil } set: { if !$0 { model.errorMessage = nil } }) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.start() }
    }
}
#endif

#Preview {
    ContentView(model: AppModel())
}
