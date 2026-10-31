import Foundation
import Testing
@testable import TaDaCore

private func data(_ text: String) -> Data { Data(text.utf8) }

private func parsed(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private let daily = VaultSettings.DailyNotes(dailyFolder: "Journal", dailyTemplate: .some(nil), weekNotes: false,
                                             weekFolder: "", weekTemplate: "Templates/Week.md")

@Test func aFullFileReadsEveryKey() {
    let settings = VaultSettings(data: data("""
    {"dailyNotes": {"dailyFolder": "Journal", "dailyTemplate": "Templates/Day.md", "weekNotes": false, "weekFolder": "", "weekTemplate": null},
     "theme": {"themeSet": "Ayu", "usesSchemePerAppearance": true, "lightScheme": "Ayu Light", "darkScheme": "Ayu Mirage"},
     "editor": {"taskLinkBoxes": false, "autocomplete": {"brackets": true, "formatting": false, "wikiLinks": true, "tags": false}}}
    """))
    #expect(settings.dailyNotes == .init(dailyFolder: "Journal", dailyTemplate: "Templates/Day.md", weekNotes: false, weekFolder: "", weekTemplate: .some(nil)))
    #expect(settings.theme == .init(themeSet: "Ayu", usesSchemePerAppearance: true, lightScheme: "Ayu Light", darkScheme: "Ayu Mirage"))
    #expect(settings.autocomplete == .init(brackets: true, formatting: false, wikiLinks: true, tags: false))
    #expect(settings.taskLinkBoxes == false)
}

@Test func noFileAnEmptyFileAndGarbageReadAsEveryKeyMissing() {
    for input in [nil, data("{}"), data(""), data("[1]"), data("not json"), data("{\"dailyNotes\": 3, \"theme\": [], \"editor\": {\"autocomplete\": \"x\"}}")] {
        #expect(VaultSettings(data: input) == VaultSettings())
    }
}

@Test func eachKeyIsReadOnItsOwn() {
    let settings = VaultSettings(data: data("""
    {"dailyNotes": {"dailyFolder": 3, "dailyTemplate": 4, "weekNotes": 1, "weekFolder": "Weeks"},
     "theme": {"themeSet": true, "usesSchemePerAppearance": "yes", "lightScheme": "Ayu Light"},
     "editor": {"taskLinkBoxes": "no", "autocomplete": {"brackets": 0, "tags": false}}}
    """))
    #expect(settings.dailyNotes == .init(weekFolder: "Weeks"))
    #expect(settings.theme == .init(lightScheme: "Ayu Light"))
    #expect(settings.autocomplete == .init(tags: false) && settings.taskLinkBoxes == nil)
}

@Test func writingSetsTheGroupsAndKeepsEverythingElse() throws {
    let existing = data("""
    {"other": {"x": 1}, "dailyNotes": {"dailyFolder": "Old", "extra": [1, 2]},
     "theme": {"themeSet": "Ayu", "extra": true}, "editor": {"font": "Mono", "autocomplete": {"brackets": false, "extra": 1}}}
    """)
    let result = VaultSettings.updated(existing, dailyNotes: daily, theme: .init(themeSet: "Nord"), autocomplete: .init(brackets: true, tags: false))
    let object = try parsed(result)
    #expect(object["other"] as? [String: Int] == ["x": 1])
    let dailyGroup = try #require(object["dailyNotes"] as? [String: Any])
    #expect(dailyGroup["dailyFolder"] as? String == "Journal" && dailyGroup["dailyTemplate"] is NSNull)
    #expect(dailyGroup["weekNotes"] as? Bool == false && dailyGroup["weekFolder"] as? String == "" && dailyGroup["extra"] as? [Int] == [1, 2])
    let themeGroup = try #require(object["theme"] as? [String: Any])
    #expect(themeGroup["themeSet"] as? String == "Nord" && themeGroup["extra"] as? Bool == true && themeGroup.count == 2)
    let editor = try #require(object["editor"] as? [String: Any])
    #expect(editor["font"] as? String == "Mono")
    let autocomplete = try #require(editor["autocomplete"] as? [String: Any])
    #expect(autocomplete["brackets"] as? Bool == true && autocomplete["tags"] as? Bool == false && autocomplete["extra"] as? Int == 1)
}

@Test func writingTheTaskLinkBoxesKeepsTheEditorsOtherKeys() throws {
    let existing = data("{\"editor\": {\"font\": \"Mono\", \"autocomplete\": {\"tags\": false}}}")
    let editor = try #require(parsed(VaultSettings.updated(existing, taskLinkBoxes: false))["editor"] as? [String: Any])
    #expect(editor["taskLinkBoxes"] as? Bool == false && editor["font"] as? String == "Mono")
    #expect((editor["autocomplete"] as? [String: Bool]) == ["tags": false])
    let both = VaultSettings(data: VaultSettings.updated(existing, autocomplete: .init(brackets: true), taskLinkBoxes: true))
    #expect(both.taskLinkBoxes == true && both.autocomplete == .init(brackets: true, tags: false))
}

@Test func writingOnlyOneGroupLeavesTheOthersAlone() throws {
    let existing = data("{\"theme\": {\"themeSet\": \"Ayu\"}}")
    let object = try parsed(VaultSettings.updated(existing, dailyNotes: daily))
    #expect(object["theme"] as? [String: String] == ["themeSet": "Ayu"])
    #expect(object["editor"] == nil)
    #expect((object["dailyNotes"] as? [String: Any])?.count == 5)
}

@Test func writingWithoutAFileMakesOneAndReadsBack() {
    let theme = VaultSettings.Theme(themeSet: "Ayu", usesSchemePerAppearance: false, lightScheme: "Ayu Light", darkScheme: "Ayu Mirage")
    let autocomplete = VaultSettings.Autocomplete(brackets: true, formatting: true, wikiLinks: false, tags: true)
    let result = VaultSettings.updated(nil, dailyNotes: daily, theme: theme, autocomplete: autocomplete)
    var expected = VaultSettings()
    (expected.dailyNotes, expected.theme, expected.autocomplete) = (daily, theme, autocomplete)
    #expect(VaultSettings(data: result) == expected)
    #expect(String(decoding: result, as: UTF8.self).hasSuffix("}\n"))
    #expect(String(decoding: result, as: UTF8.self).contains("\n  \"dailyNotes\""))
}

@Test func writingOverGarbageStartsAFreshObject() throws {
    let object = try parsed(VaultSettings.updated(data("[1]"), dailyNotes: daily))
    #expect(object.keys.sorted() == ["dailyNotes"])
}

@Test func obsidianDailyNotesReadsTheFolderAndTemplate() {
    #expect(ObsidianDailyNotes(data: data("{\"folder\": \"Journal\", \"template\": \"Templates/Daily\"}"))
            == .init(dailyFolder: "Journal", dailyTemplate: "Templates/Daily.md"))
    #expect(ObsidianDailyNotes(data: data("{\"folder\": \"\", \"template\": \"Daily.md\"}")) == .init(dailyFolder: "", dailyTemplate: "Daily.md"))
    #expect(ObsidianDailyNotes(data: data("{\"folder\": \"Journal\", \"template\": \"\"}")) == .init(dailyFolder: "Journal"))
    #expect(ObsidianDailyNotes(data: data("{\"folder\": 3, \"template\": null}")) == .init())
    #expect(ObsidianDailyNotes(data: data("nope")) == .init())
    #expect(ObsidianDailyNotes(data: nil) == .init())
}

@Test func theVaultReadsAndWritesTheSettingsFile() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        #expect(vault.readSettings() == VaultSettings())

        try vault.writeSettings(dailyNotes: daily)
        #expect(vault.readSettings().dailyNotes == daily)
        #expect(vault.readSettings().theme == .init())

        try writeFile("{\"unknown\": 1, \"theme\": {\"themeSet\": \"Ayu\"}}", Vault.settingsPath, in: folder)
        try vault.writeSettings(dailyNotes: daily)
        let settings = vault.readSettings()
        #expect(settings.dailyNotes == daily && settings.theme.themeSet == "Ayu")
        #expect(try parsed(Data(contentsOf: folder.appending(path: Vault.settingsPath)))["unknown"] as? Int == 1)

        try writeFile("{\"folder\": \"Journal\", \"template\": \"Daily\"}", ".obsidian/daily-notes.json", in: folder)
        #expect(vault.readObsidianDailyNotes() == .init(dailyFolder: "Journal", dailyTemplate: "Daily.md"))
    }
}
