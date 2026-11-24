// The open file as the user's activity: Handoff to Ta Da on another device with the same folder, and the entity on screen
// for Siri.
import AppIntents
import SwiftUI
import TaDaCore

enum FileActivity {
    /// In `NSUserActivityTypes`.
    static let type = (Bundle.main.bundleIdentifier ?? "") + ".file"
}

extension View {
    /// Publishes the file at `path` while the view shows it.
    func fileActivity(_ model: AppModel, path: String?) -> some View {
        let item = path.flatMap { model.index[$0] }
        return userActivity(FileActivity.type, isActive: item != nil) { activity in
            guard let item else { return }
            activity.title = item.title
            activity.userInfo = ["path": item.path]
            activity.requiredUserInfoKeys = ["path"]
            activity.isEligibleForHandoff = true
            switch item.properties.kind {
            case .task: activity.appEntityIdentifier = EntityIdentifier(for: TaskEntity.self, identifier: item.path)
            case .project, .area: activity.appEntityIdentifier = EntityIdentifier(for: ParentEntity.self, identifier: item.path)
            case .note: break
            }
        }
    }

    /// Opens the file a Handoff names, when the open folder has it.
    func continuesFileActivity(_ model: AppModel) -> some View {
        onContinueUserActivity(FileActivity.type) { activity in
            guard let path = activity.userInfo?["path"] as? String, model.index[path] != nil else { return }
            model.reveal(.file(path))
        }
    }
}
