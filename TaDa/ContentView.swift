// Root view: the folder picker until a folder is open, then sidebar + workspace (on iOS, the tabs).
// Applies the theme.
import SwiftUI
import TaDaCore

#if os(macOS)
struct ContentView: View {
    @Bindable var model: AppModel
    @State private var quickSwitcher = QuickSwitcher()

    var body: some View {
        Group {
            switch model.state {
            case .noFolder, .failed:
                FolderPickerView(model: model)
            case .loading, .ready:
                SidebarSplitView(model: model)
            }
        }
        .imageDialogs(model)
        .onChange(of: model.quickSwitcherRequest) { quickSwitcher.toggle(model) }
        .sheet(item: Binding { model.trashConfirmation.flatMap { $0.images.isEmpty ? nil : $0 } }
                         set: { if $0 == nil { model.trashConfirmation = nil } }) { request in
            DeleteFilesDialog(model: model, request: request)
                .presentationBackground(model.theme.color(model.theme.isDark ? \.side : \.bg))
        }
        .sheet(item: $model.convertRequest) { request in
            ConvertSheet(model: model, request: request)
                .presentationBackground(model.theme.color(model.theme.isDark ? \.side : \.bg))
        }
        .sheet(item: Binding { model.completionConfirmation }
                         set: { if $0 == nil, let request = model.completionConfirmation { Task { await model.answerCompletion(request, tasksAs: nil) } } }) { request in
            CompletionDialog(model: model, request: request)
                .presentationBackground(model.theme.color(model.theme.isDark ? \.side : \.bg))
        }
        .themed(by: model)
        // No toolbar fill: each column's own colour runs up under the toolbar (proven in the M1 spike).
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        // In full screen the toolbar shows only under the pointer, so the columns reach the top of the screen.
        .windowToolbarFullScreenVisibility(.onHover)
        .containerBackground(model.theme.color(\.bg), for: .window)
        .frame(minWidth: WorkspaceView.minWidth, minHeight: 480)
        .alert("Ta Da", isPresented: Binding { model.errorMessage != nil } set: { if !$0 { model.errorMessage = nil } }) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert(TrashConfirmationText(model: model).title,
               isPresented: Binding { model.trashConfirmation?.images.isEmpty == true } set: { if !$0 { model.trashConfirmation = nil } },
               presenting: model.trashConfirmation) { request in
            Button(request.count == 1 ? "Delete 1 File" : "Delete \(request.count) Files", role: .destructive) { Task { await model.confirmTrash(request) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(TrashConfirmationText(model: model).message)
        }
        .alert(folderTrashTitle,
               isPresented: Binding { model.folderTrashConfirmation != nil } set: { if !$0 { model.folderTrashConfirmation = nil } },
               presenting: model.folderTrashConfirmation) { request in
            Button("Move to Trash", role: .destructive) { Task { await model.confirmTrashFolder(request) } }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(request.count == 0 ? "It holds no notes." : "Its \(request.count == 1 ? "note goes" : "\(request.count) notes go") with it. You can restore them from Trash.")
        }
        .task { await model.start() }
    }

    private var folderTrashTitle: String {
        "Move “\(model.folderTrashConfirmation.map { Item.title(ofPath: $0.path) } ?? "")” to the Trash?"
    }
}

#else
struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.state {
            case .noFolder, .failed:
                PhoneOnboardingView(model: model)
            case .loading:
                ProgressView("Reading \(model.folderDisplayName)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(model.theme.color(\.bg))
            case .ready:
                PhoneRootView(model: model)
            }
        }
        .imageDialogs(model)
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
