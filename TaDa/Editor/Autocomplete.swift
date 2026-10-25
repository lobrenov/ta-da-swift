// What the live editor completes as you type: Settings ▸ Editor's Autocomplete switches.
import Foundation

struct Autocomplete: Equatable {
    /// `(`, `[` and `{` add their closer.
    var brackets = true
    /// `*`, `**`, `_`, `__`, `~~`, `==` and `` ` `` add their closing marker.
    var formatting = true
    /// `[[` adds `]]`, for links and `![[` embeds.
    var wikiLinks = true
    /// `#` and a letter list the tags in use.
    var tags = true

    init() {}

    /// Reads the settings' dictionary; a missing switch is on.
    init(_ dictionary: [String: Any]?) {
        brackets = dictionary?["brackets"] as? Bool ?? true
        formatting = dictionary?["formatting"] as? Bool ?? true
        wikiLinks = dictionary?["wikiLinks"] as? Bool ?? true
        tags = dictionary?["tags"] as? Bool ?? true
    }
}
