import Foundation

/// The settings that belong to the folder, in `Ta Da/settings.json` (see Settings in `docs/file-format.md`). Each key
/// is nil when it's missing or of the wrong type. Theme values are names.
public struct VaultSettings: Equatable, Sendable {
    /// A template is nil for none: its outer optional is nil when the key is missing or of the wrong type.
    public struct DailyNotes: Equatable, Sendable {
        public var dailyFolder: String?
        public var dailyTemplate: String??
        public var weekNotes: Bool?
        public var weekFolder: String?
        public var weekTemplate: String??

        public init(dailyFolder: String? = nil, dailyTemplate: String?? = nil, weekNotes: Bool? = nil,
                    weekFolder: String? = nil, weekTemplate: String?? = nil) {
            self.dailyFolder = dailyFolder
            self.dailyTemplate = dailyTemplate
            self.weekNotes = weekNotes
            self.weekFolder = weekFolder
            self.weekTemplate = weekTemplate
        }
    }

    public struct Theme: Equatable, Sendable {
        public var themeSet: String?
        public var usesSchemePerAppearance: Bool?
        public var lightScheme: String?
        public var darkScheme: String?

        public init(themeSet: String? = nil, usesSchemePerAppearance: Bool? = nil, lightScheme: String? = nil, darkScheme: String? = nil) {
            self.themeSet = themeSet
            self.usesSchemePerAppearance = usesSchemePerAppearance
            self.lightScheme = lightScheme
            self.darkScheme = darkScheme
        }
    }

    public struct Autocomplete: Equatable, Sendable {
        public var brackets: Bool?
        public var formatting: Bool?
        public var wikiLinks: Bool?
        public var tags: Bool?

        public init(brackets: Bool? = nil, formatting: Bool? = nil, wikiLinks: Bool? = nil, tags: Bool? = nil) {
            self.brackets = brackets
            self.formatting = formatting
            self.wikiLinks = wikiLinks
            self.tags = tags
        }
    }

    public var dailyNotes = DailyNotes()
    public var theme = Theme()
    public var autocomplete = Autocomplete()

    public init() {}

    /// Reads the file's data; nil, or data that isn't a JSON object, reads as every key missing.
    public init(data: Data?) {
        let root = Self.object(data)
        let daily = root["dailyNotes"] as? [String: Any] ?? [:]
        dailyNotes = DailyNotes(
            dailyFolder: daily["dailyFolder"] as? String, dailyTemplate: Self.template(daily["dailyTemplate"]),
            weekNotes: Self.bool(daily["weekNotes"]), weekFolder: daily["weekFolder"] as? String,
            weekTemplate: Self.template(daily["weekTemplate"]))
        let theme = root["theme"] as? [String: Any] ?? [:]
        self.theme = Theme(
            themeSet: theme["themeSet"] as? String, usesSchemePerAppearance: Self.bool(theme["usesSchemePerAppearance"]),
            lightScheme: theme["lightScheme"] as? String, darkScheme: theme["darkScheme"] as? String)
        let editor = root["editor"] as? [String: Any] ?? [:]
        let autocomplete = editor["autocomplete"] as? [String: Any] ?? [:]
        self.autocomplete = Autocomplete(
            brackets: Self.bool(autocomplete["brackets"]), formatting: Self.bool(autocomplete["formatting"]),
            wikiLinks: Self.bool(autocomplete["wikiLinks"]), tags: Self.bool(autocomplete["tags"]))
    }

    /// `data` with the keys of each group given (the ones a side owns) set, and everything else kept, unknown keys and
    /// groups included. A nil key in a group isn't written. Pretty-printed JSON with a final newline.
    public static func updated(_ data: Data?, dailyNotes: DailyNotes? = nil, theme: Theme? = nil, autocomplete: Autocomplete? = nil) -> Data {
        var root = object(data)
        if let dailyNotes {
            root["dailyNotes"] = set(root["dailyNotes"], [
                "dailyFolder": dailyNotes.dailyFolder, "dailyTemplate": value(dailyNotes.dailyTemplate), "weekNotes": dailyNotes.weekNotes,
                "weekFolder": dailyNotes.weekFolder, "weekTemplate": value(dailyNotes.weekTemplate),
            ])
        }
        if let theme {
            root["theme"] = set(root["theme"], [
                "themeSet": theme.themeSet, "usesSchemePerAppearance": theme.usesSchemePerAppearance,
                "lightScheme": theme.lightScheme, "darkScheme": theme.darkScheme,
            ])
        }
        if let autocomplete {
            var editor = root["editor"] as? [String: Any] ?? [:]
            editor["autocomplete"] = set(editor["autocomplete"], [
                "brackets": autocomplete.brackets, "formatting": autocomplete.formatting,
                "wikiLinks": autocomplete.wikiLinks, "tags": autocomplete.tags,
            ])
            root["editor"] = editor
        }
        let json = (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return json + Data("\n".utf8)
    }

    /// `group` (replaced by an empty object if it isn't one) with each non-nil value set.
    private static func set(_ group: Any?, _ values: KeyValuePairs<String, Any?>) -> [String: Any] {
        var group = group as? [String: Any] ?? [:]
        for (key, value) in values { if let value { group[key] = value } }
        return group
    }

    private static func value(_ template: String??) -> Any? {
        guard let template else { return nil }
        return template ?? NSNull()
    }

    private static func object(_ data: Data?) -> [String: Any] {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
    }

    /// Only JSON `true` and `false`, not 1 and 0.
    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func template(_ value: Any?) -> String?? {
        if value is NSNull { return .some(nil) }
        return (value as? String).map { .some($0) }
    }
}

/// Obsidian's Daily notes setting, in `.obsidian/daily-notes.json`: the folder, and the template as a note's path.
public struct ObsidianDailyNotes: Equatable, Sendable {
    public var dailyFolder: String?
    public var dailyTemplate: String?

    public init(dailyFolder: String? = nil, dailyTemplate: String? = nil) {
        self.dailyFolder = dailyFolder
        self.dailyTemplate = dailyTemplate
    }

    /// Reads the file's data. An empty template is none; one without `.md` gets it.
    public init(data: Data?) {
        let root = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        dailyFolder = root?["folder"] as? String
        if let template = root?["template"] as? String, !template.isEmpty {
            dailyTemplate = template.hasSuffix(".md") ? template : template + ".md"
        }
    }
}

extension Vault {
    public static let settingsPath = home + "/settings.json"
    static let obsidianDailyNotesPath = ".obsidian/daily-notes.json"

    /// The folder's settings; a missing or unreadable file reads as every key missing.
    public func readSettings() -> VaultSettings {
        VaultSettings(data: (try? CoordinatedFileIO.read(url(for: Self.settingsPath))).map { Data($0.utf8) })
    }

    /// Obsidian's Daily notes setting; a missing or unreadable file reads as nothing set.
    public func readObsidianDailyNotes() -> ObsidianDailyNotes {
        ObsidianDailyNotes(data: (try? CoordinatedFileIO.read(url(for: Self.obsidianDailyNotesPath))).map { Data($0.utf8) })
    }

    /// Sets the keys of the groups given in the settings file, creating it if needed (see `VaultSettings.updated`), in
    /// one coordinated access.
    public func writeSettings(dailyNotes: VaultSettings.DailyNotes? = nil, theme: VaultSettings.Theme? = nil,
                              autocomplete: VaultSettings.Autocomplete? = nil) throws {
        let url = url(for: Self.settingsPath)
        func updated(_ data: Data?) -> Data {
            VaultSettings.updated(data, dailyNotes: dailyNotes, theme: theme, autocomplete: autocomplete)
        }
        do {
            try CoordinatedFileIO.create(updated(nil), at: url)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            try CoordinatedFileIO.update(url) { String(decoding: updated(Data($0.utf8)), as: UTF8.self) }
        }
    }
}
