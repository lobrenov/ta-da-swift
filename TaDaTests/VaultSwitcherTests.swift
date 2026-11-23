import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct VaultSwitcherTests {
    let first: TestFolder
    let second: TestFolder

    init() throws {
        first = try TestFolder(["Ta Da/tasks/One.md": "---\ntype: task\nstatus: Doing\n---\n"])
        second = try TestFolder(["Ta Da/tasks/Two.md": "---\ntype: task\nstatus: Doing\n---\n"])
    }

    /// A model on `first`'s settings, having opened `second` then `first`.
    private func model() async -> AppModel {
        let model = AppModel(defaults: first.defaults)
        await model.choose(second.url)
        await model.choose(first.url)
        return model
    }

    private func name(_ folder: TestFolder) -> String { folder.url.lastPathComponent }

    @Test func openedFoldersAreRememberedMostRecentFirst() async {
        let model = await model()
        #expect(model.vaults.map(\.name) == [name(first), name(second)])
        #expect(model.vaults.map(\.isOpen) == [true, false])
        await model.choose(second.url)
        #expect(model.vaults.map(\.name) == [name(second), name(first)], "choosing a remembered folder moves it up")
        let relaunched = AppModel(defaults: first.defaults)
        await relaunched.start()
        #expect(relaunched.vaults.map(\.name) == [name(second), name(first)])
    }

    @Test func switchingOpensARememberedVault() async throws {
        let model = await model()
        await model.switchVault(to: try #require(model.vaults.last))
        #expect(model.state == .ready)
        #expect(model.index.tasks.map(\.title) == ["Two"])
        #expect(model.vaults.map(\.name) == [name(second), name(first)])

        let relaunched = AppModel(defaults: first.defaults)
        await relaunched.start()
        #expect(relaunched.index.tasks.map(\.title) == ["Two"])
    }

    @Test func aMissingVaultStaysListedUntilForgotten() async throws {
        let model = await model()
        try FileManager.default.removeItem(at: second.url)
        model.reloadVaults()
        let missing = try #require(model.vaults.last)
        #expect(missing.name == name(second) && missing.isMissing)

        model.forget(missing)
        #expect(model.vaults.map(\.name) == [name(first)])
        model.forget(try #require(model.vaults.first))
        #expect(model.vaults.map(\.name) == [name(first)], "the open vault isn't forgotten")
    }

    @Test func aSwitchToAFolderGoneSinceTheListWasReadKeepsTheOpenVault() async throws {
        let model = await model()
        let stale = try #require(model.vaults.last)
        let saved = first.defaults.data(forKey: AppModel.Keys.bookmark)
        try FileManager.default.removeItem(at: second.url)
        await model.switchVault(to: stale)
        #expect(model.state == .ready && model.index.tasks.map(\.title) == ["One"])
        #expect(first.defaults.data(forKey: AppModel.Keys.bookmark) == saved)
        #expect(model.errorMessage != nil)
        #expect(model.vaults.last?.isMissing == true)
    }

    @Test func switchingClearsThePickedFiles() async throws {
        try first.write("---\ntype: task\nstatus: Doing\n---\n", "Ta Da/tasks/Two.md")
        let model = await model()
        model.toggleSelection("Ta Da/tasks/One.md")
        model.toggleSelection("Ta Da/tasks/Two.md")
        #expect(model.multiSelection.count == 2)
        await model.switchVault(to: try #require(model.vaults.last))
        #expect(model.multiSelection.isEmpty)
    }

    @Test func theSavedFolderStartsTheList() async throws {
        first.defaults.set(try Vault.bookmark(for: first.url), forKey: AppModel.Keys.bookmark)
        let model = AppModel(defaults: first.defaults)
        await model.start()
        #expect(model.vaults.map(\.name) == [name(first)])
    }

    @Test func aVaultsLocationNamesWhereItIs() throws {
        let local = first.url.appending(path: "File Provider Storage/Vault")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        #expect(RememberedVault(bookmark: try Vault.bookmark(for: local), openPath: nil).location == "On My iPhone")
        let other = RememberedVault(bookmark: try Vault.bookmark(for: second.url), openPath: nil)
        #expect(other.location == second.url.deletingLastPathComponent().lastPathComponent && !other.isInICloud)
    }

    @Test func recentFilesAreKeptPerVault() async throws {
        first.defaults.set(["Ta Da/tasks/One.md"], forKey: AppModel.Keys.recentFiles)
        let model = AppModel(defaults: first.defaults)
        await model.choose(first.url)
        #expect(model.recentFiles == ["Ta Da/tasks/One.md"], "a list kept for every vault goes to the first one opened")

        await model.choose(second.url)
        #expect(model.recentFiles.isEmpty)
        model.selection = "Ta Da/tasks/Two.md"
        await model.loading?.value
        #expect(model.recentFiles == ["Ta Da/tasks/Two.md"])

        await model.switchVault(to: try #require(model.vaults.last))
        #expect(model.recentFiles == ["Ta Da/tasks/One.md"])
    }
}
