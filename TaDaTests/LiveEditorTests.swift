import Foundation
import Testing
@testable import TaDa

/// The live editor draws a link as resolved when its title, read as the core reads it, names a file.
struct LiveEditorTests {
    @Test func linksResolveByTheirTitleAsTheCoreReadsIt() {
        let resolver = TitleResolver(titles: ["ta da mvp"])
        for target in ["Ta Da MVP", "ta da mvp", "Ta Da MVP.md", "projects/Ta Da MVP.md", "Ta Da MVP#Goals", " Ta Da MVP "] {
            #expect(resolver.resolve(displayName: target, range: NSRange()) != nil, "\(target)")
        }
        for target in ["Ta Da", "#Goals", "Ta Da MVP.txt"] {
            #expect(resolver.resolve(displayName: target, range: NSRange()) == nil, "\(target)")
        }
    }
}
