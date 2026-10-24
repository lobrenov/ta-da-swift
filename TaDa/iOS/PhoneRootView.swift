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
        TabView(selection: Binding(get: { nav.tab }, set: select)) {
            Tab("Agenda", systemImage: "calendar", value: PhoneTab.agenda) {
                stack(.agenda) { PhoneAgendaScreen(model: model) }
            }
            Tab("Tasks", systemImage: "checkmark.square", value: PhoneTab.tasks) {
                stack(.tasks) { PhoneTasksScreen(model: model) }
            }
            Tab("Tags", systemImage: "tag", value: PhoneTab.tags) {
                stack(.tags) { PhoneTagsScreen(model: model) }
            }
            Tab("Notes", systemImage: "doc.text", value: PhoneTab.notes) {
                stack(.notes) { PhoneNotesScreen(model: model) }
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
            case let .tags(path): PhoneTagSheet(model: model, path: path)
            }
        }
        .alert(trashTitle, isPresented: Binding { model.trashConfirmation?.images.isEmpty == true }
                                                set: { if !$0 { model.trashConfirmation = nil } },
               presenting: model.trashConfirmation) { request in
            Button("Move \(request.count == 1 ? "1 File" : "\(request.count) Files") to Trash", role: .destructive) {
                trash(request)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(TrashConfirmationText(model: model).message)
        }
        .sheet(item: Binding { model.trashConfirmation.flatMap { $0.images.isEmpty ? nil : $0 } }
                         set: { if $0 == nil { model.trashConfirmation = nil } }) { request in
            PhoneDeleteFilesSheet(model: model, request: request) { trash(request, images: $0) }
        }
        .confirmationDialog(model.completionConfirmation.map { CompletionText(request: $0).title } ?? "",
                            isPresented: Binding { model.completionConfirmation != nil }
                                                 set: { if !$0, let request = model.completionConfirmation { answer(request, nil) } },
                            titleVisibility: .visible, presenting: model.completionConfirmation) { request in
            let text = CompletionText(request: request)
            Button(text.button(text.choices.primary)) { answer(request, text.choices.primary) }
            Button(text.button(text.choices.secondary)) { answer(request, text.choices.secondary) }
            Button("Cancel", role: .cancel) { answer(request, nil) }
        } message: { request in
            Text(CompletionText(request: request).message)
        }
        .environment(nav)
        .phoneHaptics(nav, enabled: model.haptics)
        .onChange(of: nav.tab) { nav.endPicking() }
    }

    /// Picks `tab`; picking the selected one again pops its screens, or takes the Agenda to today.
    private func select(_ tab: PhoneTab) {
        switch nav.reselection(of: tab, agenda: model.agendaSelection, today: model.today) {
        case .popToRoot: nav.stacks[tab] = []
        case .showAgendaToday:
            nav.play(.pick)
            withAnimation(AgendaMotion.spring) { model.showAgendaToday() }
        case nil: nav.tab = tab
        }
    }

    /// Deletes what `request` asked about, and `images`, then drops the screens of the files that went.
    private func trash(_ request: AppModel.TrashConfirmation, images: [String] = []) {
        nav.play(.trash)
        Task {
            await model.confirmTrash(request, images: images)
            nav.dropScreens { model.index[$0] == nil }
        }
    }

    /// Answers the completion question once: it's cleared first.
    private func answer(_ request: AppModel.CompletionConfirmation, _ status: Status?) {
        guard model.completionConfirmation?.id == request.id else { return }
        model.completionConfirmation = nil
        if status != nil { nav.play(.complete) }
        Task { await model.answerCompletion(request, tasksAs: status) }
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
                    case .loose: PhoneTaskListScreen(model: model)
                    case let .project(path): PhoneProjectScreen(model: model, path: path)
                    case let .area(path): PhoneAreaScreen(model: model, path: path)
                    case let .settings(section): PhoneSettingsScreen(model: model, section: section)
                    case .integrations: PhoneIntegrationsScreen(store: model.integrations)
                    case .logbook: PhoneLogbookScreen(model: model)
                    case .attachments: PhoneAttachmentsScreen(model: model)
                    case let .attachment(path): PhoneAttachmentScreen(model: model, path: path)
                    case .trash: PhoneTrashScreen(model: model)
                    case let .tag(path): PhoneTagScreen(model: model, path: path)
                    case let .folder(path): PhoneFolderScreen(model: model, path: path)
                    }
                }
            }
        }
    }
}
#endif
