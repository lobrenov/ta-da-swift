// The lists with a Group choice, and how their sections fold.
import TaDaCore

/// A list with a Group choice. Every project shares one.
enum GroupedList: String {
    case today, loose, project

    /// The menu's choices, in order.
    var groupings: [Grouping] {
        switch self {
        case .today: [.project, .status, .open]
        case .loose, .project: [.status, .date, .open]
        }
    }

    var defaultGrouping: Grouping {
        switch self {
        case .today: .project
        case .loose: .status
        case .project: .open
        }
    }

    /// The key Today's and Loose tasks' folds are kept under; a project's are under its path.
    var foldKey: String { ":" + rawValue }
}

extension ListSection {
    /// The name its fold is kept under. Open's groups keep the names projects folded them under before grouping.
    func foldName(_ grouping: Grouping) -> String {
        grouping == .open ? title : "\(grouping.rawValue): \(title)"
    }

    /// Done, Cancelled and Date's Completed start folded.
    func startsFolded(_ grouping: Grouping) -> Bool {
        switch kind {
        case .status(let status): status.isClosed
        case .completed: grouping == .date
        case .date, .open: false
        }
    }
}
