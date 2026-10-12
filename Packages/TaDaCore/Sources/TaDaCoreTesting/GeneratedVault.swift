import Foundation
import TaDaCore

/// A large, varied, deterministic folder of tasks and projects for scale tests: every status, dates
/// around `today`, contexts, subtasks, links, unresolved projects, nested folders and plain notes
/// that Ta Da must skip.
public enum GeneratedVault {
    /// `items` Ta Da files (one project per 20) plus `notes` plain Markdown notes.
    public static func files(items: Int = 1000, notes: Int = 200, today: LocalDate) -> [(path: String, text: String)] {
        var random = Random(seed: 42)
        let projectCount = max(items / 20, 1)
        let projects = (1...projectCount).map { String(format: "Project %02d", $0) }
        let words = ["review", "draft", "call", "fix", "plan", "book", "email", "update", "clean", "order", "renew", "ship"]
        let contexts = ["@computer", "@phone", "@home", "@errands", "@office"]
        let statuses = ["Not Started", "Not Started", "Not Started", "Doing", "Blocked", "Done", "Done", "Cancelled"]
        var files: [(String, String)] = []

        for (i, title) in projects.enumerated() {
            var fm = ["type: project", "status: \(i % 7 == 0 ? "Done" : i % 2 == 0 ? "Doing" : i % 10 == 1 ? "Ongoing" : "Not Started")", "area: Area \(i % 5)"]
            if i % 3 == 0 { fm.append("deadline: \(today.adding(days: random.next(in: -10...90)))") }
            files.append(("projects/\(title).md", file(fm, "The \(title.lowercased()) project.\n\nNotes and context for it.\n")))
        }

        for n in 1...(items - projectCount) {
            let title = "Task \(String(format: "%04d", n)) \(words[random.next(in: 0...words.count - 1)])"
            let status = statuses[random.next(in: 0...statuses.count - 1)]
            var fm = ["type: task", "status: \(status)"]
            let link = random.next(in: 0...99)
            if link < 70 {
                fm.append("project: \"[[\(projects[random.next(in: 0...projectCount - 1)])]]\"")
            } else if link < 72 {
                fm.append("project: \"[[Missing project]]\"")
            }
            if random.next(in: 0...9) < 4 {
                fm.append("contexts:")
                fm.append("  - \"\(contexts[random.next(in: 0...contexts.count - 1)])\"")
            }
            fm.append("createdDate: \(today.adding(days: -random.next(in: 1...200)))")
            if status == "Done" || status == "Cancelled" { fm.append("completedDate: \(today.adding(days: -random.next(in: 0...30)))") }
            if random.next(in: 0...9) < 5 { fm.append("dueDate: \(today.adding(days: random.next(in: -30...60)))") }
            if random.next(in: 0...9) < 2 { fm.append("deadline: \(today.adding(days: random.next(in: -10...90)))") }
            if random.next(in: 0...32) == 0 { fm.append("repeat: weekly") }

            var body = "Something to \(words[n % words.count]) before it's too late.\n"
            let subtasks = random.next(in: 0...6)
            if subtasks > 0 {
                body += "\n" + (0..<subtasks).map { "- [\(random.next(in: 0...2) == 0 ? "x" : " ")] Step \($0 + 1)\n" }.joined()
            }
            if n > 1, random.next(in: 0...9) == 0 { body += "\nSee [[Task \(String(format: "%04d", n - 1))]].\n" }
            let folder = n % 10 == 0 ? "Areas/Area \(n % 5)/tasks" : "tasks"
            files.append(("\(folder)/\(title).md", file(fm, body)))
        }

        for n in 0..<notes {
            let text = n % 2 == 0 ? "# Note \(n)\n\nJust a note, linking [[Project 01]].\n" : file(["tags: [journal]"], "Journal entry \(n).\n")
            files.append(("notes/Note \(n).md", text))
        }
        return files
    }

    /// Writes the files under `root`, creating folders as needed.
    public static func write(to root: URL, items: Int = 1000, notes: Int = 200, today: LocalDate) throws {
        for (path, text) in files(items: items, notes: notes, today: today) {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }

    private static func file(_ frontmatter: [String], _ body: String) -> String {
        "---\n" + frontmatter.map { $0 + "\n" }.joined() + "---\n" + body
    }

    /// A tiny linear congruential generator, so the vault is the same on every run.
    private struct Random {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next(in range: ClosedRange<Int>) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return range.lowerBound + Int((state >> 33) % UInt64(range.count))
        }
    }
}
