import Foundation
import Testing
@testable import TaDaCore
import TaDaCoreTesting

/// Scale: a generated folder of 1,000 tasks and projects plus 200 plain notes. Timings are printed; the
/// limits are loose enough for a debug build on a busy machine and catch only accidental O(n²) work.
struct LargeVaultTests {
    static let today = LocalDate("2026-10-03")!

    /// Elapsed seconds, printed with a label.
    @discardableResult
    private func time<T>(_ label: String, _ work: () async throws -> T) async rethrows -> (T, Double) {
        let clock = ContinuousClock()
        var result: T?
        let elapsed = try await clock.measure { result = try await work() }
        let seconds = Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds)
        print(String(format: "LargeVault %@: %.1f ms", label, seconds * 1000))
        return (result!, seconds)
    }

    @Test func generatedVaultHasEverythingTheAppHandles() {
        let files = GeneratedVault.files(today: Self.today)
        #expect(files.count == 1200)
        let items = files.compactMap { Item(parsing: $0.text, path: $0.path) }
        #expect(items.count == 1200)
        let index = VaultIndex(items)
        #expect(index.notes.count == 200)
        #expect(index.projects.count == 50)
        #expect(Set(index.tasks.map(\.properties.status)) == Set(Status.choices(for: .task)))
        #expect(index.projects.contains { $0.properties.status == .ongoing })
        #expect(index.tasks.contains { index.warnings(for: $0).contains(.unresolvedProject("Missing project")) })
        #expect(index.tasks.contains { $0.path.hasPrefix("Areas/") })
        #expect(!index.today(Self.today).isEmpty && !index.upcoming(after: Self.today).isEmpty && !index.loose().isEmpty)
        #expect(GeneratedVault.files(today: Self.today).map(\.text) == files.map(\.text), "the same on every run")
    }

    @Test func aThousandFilesLoadAndQueryQuickly() async throws {
        try await withTemporaryFolder { folder in
            try GeneratedVault.write(to: folder, today: Self.today)
            let vault = Vault(root: folder)

            let (dates, scanTime) = await time("modification dates") { vault.modificationDates() }
            #expect(dates.count == 1200)
            let (index, loadTime) = await time("load index") { await vault.loadIndex() }
            #expect(index.items.count == 1200)
            let (changes, refreshTime) = await time("refresh, nothing changed") { vault.changes(since: dates) }
            #expect(changes.isEmpty)
            let (empty, folderScanTime) = await time("empty folders") { vault.emptyFolders() }
            #expect(empty.isEmpty)
            #expect(scanTime < 1 && loadTime < 4 && refreshTime < 1 && folderScanTime < 1)

            let today = Self.today
            let (_, queryTime) = await time("sidebar and lists") {
                _ = index.today(today).count
                _ = index.loose().count
                _ = index.activeProjects()
                _ = index.grouped(index.today(today))
                _ = index.upcoming(after: today)
                _ = index.search("review")
                _ = index.folderTree(folders: empty)
                _ = index.notes(in: "notes")
            }
            #expect(queryTime < 0.5)

            var patched = index
            let task = try #require(index["Ta Da/tasks/Task 0001 call.md"] ?? index.tasks.first)
            let edited = try #require(Item(parsing: try vault.read(task.path) + "\nMore.\n", path: task.path))
            let (_, updateTime) = await time("index update (one keystroke)") { patched.update(edited) }
            #expect(updateTime < 0.1)
            let all = Array(index.items.values)
            let (_, batchTime) = await time("index update (every file changed)") { for item in all { patched.update(item) } }
            #expect(batchTime < 0.5)
        }
    }

    @Test func attachmentGroupsListQuicklyWithEveryFileEmbeddingImages() async throws {
        try await withTemporaryFolder { folder in
            try GeneratedVault.write(to: folder, today: Self.today)
            let vault = Vault(root: folder)
            for number in 0..<300 { try writeFile("x", "Ta Da/attachments/Image \(number).png", in: folder) }
            for number in 0..<500 {
                try writeFile("---\ntype: task\n---\n![[Image \(number % 300).png]] ![[Image \((number * 7) % 300).png]]\n", "Ta Da/tasks/Embeds \(number).md", in: folder)
            }
            let index = await vault.loadIndex()
            let (groups, groupTime) = await time("attachment groups") { await vault.attachmentGroups(index: index, trashed: []) }
            #expect(groups.candidates.isEmpty && groups.inUse.count == 300)
            #expect(groupTime < 1)
        }
    }

    /// Writes the vault for trying it in the app:
    /// `TADA_GENERATE_VAULT=/path/to/folder swift test --package-path Packages/TaDaCore --filter writeGeneratedVault`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TADA_GENERATE_VAULT"] != nil))
    func writeGeneratedVault() throws {
        let folder = URL(filePath: ProcessInfo.processInfo.environment["TADA_GENERATE_VAULT"]!, directoryHint: .isDirectory)
        try GeneratedVault.write(to: folder, today: LocalDate(Date()))
    }
}
