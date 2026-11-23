import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct VaultMenuTests {
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

    @Test func rowsAreTheVaultsThenOpenAnotherVault() async {
        let model = await model()
        let sections = VaultMenuItem.sections(for: model.vaults)
        #expect(sections.map(\.label) == ["Vaults on this Mac", nil])
        #expect(sections[0].items.map(\.title) == model.vaults.map(\.name))
        #expect(sections[1].items.map(\.title) == ["Open Another Vault…"])
        #expect(sections[0].items.map(\.accessibilityValue).first?.hasPrefix("Current, ") == true)
    }

    @Test func aMissingVaultIsNotedNotFound() async throws {
        let model = await model()
        try FileManager.default.removeItem(at: second.url)
        model.reloadVaults()
        let missing = try #require(model.vaults.last)
        #expect(VaultMenuItem.vault(missing).accessibilityValue == "Not found")
    }

    @Test func removeFromListIsNotOfferedForTheOpenVault() async throws {
        let model = await model()
        let open = try #require(model.vaults.first)
        let other = try #require(model.vaults.last)
        #expect(VaultMenu.actions(for: open, model: model).map(\.title) == ["Reveal in Finder"])
        let actions = VaultMenu.actions(for: other, model: model)
        #expect(actions.map(\.title) == ["Reveal in Finder", "Remove from List"])
        actions[1].run()
        #expect(model.vaults.map(\.name) == [open.name])
    }

    @Test func revealInFinderIsDisabledForAMissingVault() async throws {
        let model = await model()
        #expect(VaultMenu.actions(for: try #require(model.vaults.last), model: model)[0].isEnabled)
        try FileManager.default.removeItem(at: second.url)
        model.reloadVaults()
        #expect(!VaultMenu.actions(for: try #require(model.vaults.last), model: model)[0].isEnabled)
    }

    @Test func pickingOpensAVaultOrTheFolderPicker() async throws {
        let model = await model()
        let menu = VaultMenu()
        menu.pick(.vault(try #require(model.vaults.last)), model: model)
        #expect(!menu.isChoosingFolder)
        for _ in 0..<250 where model.index.tasks.map(\.title) != ["Two"] { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.index.tasks.map(\.title) == ["Two"])

        menu.pick(.openAnother, model: model)
        #expect(menu.isChoosingFolder)
        menu.isChoosingFolder = false
        try FileManager.default.removeItem(at: first.url)
        model.reloadVaults()
        let missing = model.vaults.first { $0.isMissing }
        menu.pick(.vault(try #require(missing)), model: model)
        #expect(menu.isChoosingFolder, "a missing vault opens the folder picker")
    }
}
