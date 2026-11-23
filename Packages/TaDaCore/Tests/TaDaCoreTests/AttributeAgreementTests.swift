import MarkdownEngineSyntax
import Testing
@testable import TaDaCore

/// The task lines of the editor package's `spec/grammar/task-attributes.md`.
private let specLines = [
    "due >2026-10-02 and more",
    "parent @[[Ta Da MVP]] now",
    "both >2026-02-28 @[[Home|Casa]] @[[Work]] >2026-03-01",
    "none: x>2026-10-02 \\>2026-10-03 `>2026-10-04` >2026-02-29 >2026-13-01 >2026-10-0 >2026-10-021 >2026-10-02x",
    "leap >2028-02-29.",
    "spaced @ [[Home]] and x@[[Home]]",
    "#tag >2026-10-02 **bold >2026-10-03 @[[Work]]**",
    "read through **a >2026-10-09** and ==b @[[Home]]== ~~c~~ $d$",
    "draft >2026-10-09-draft and _x_",
    "nbsp >2026-10-09 tab\t>2026-10-10",
    "zero >0000-01-01 later >0001-01-01",
    "link [a [b] >2026-10-09 c](u.md) ![i >2026-10-09](p.png) >2026-10-10",
    "first >2026-10-11 second >2026-10-12 @[[A]] @[[B]]",
]

/// The text of `InlineAttributesTests`' inputs.
private let coreTexts = [
    "Call Sam >2026-10-09 @[[Ta Da MVP]]", ">2026-10-09 call", "@[[Home]] call", "a>2026-10-09", "mail@[[Home]]", "a\t>2026-10-09",
    "a >2026-10-09 >2026-11-01 @[[A]] @[[B]]", "a >2026-02-30 >2026-11-01", "a >2026-13-01", "a >2026-10-9", "a >soon",
    "a >2026-10-091", "a >2026-10-09, b", "a @ [[Home]]", "a @Home", "a @[[Home", "a @[[]]", "a @[[#heading]]",
    "a @[[Ta Da MVP|the MVP]]", "a @[[Ta Da MVP#Goals]]", "a @[[Projects/Ta Da MVP.md]]", "a `>2026-10-09 @[[A]]` b",
    "a ``x ` >2026-10-09`` b", "a `unclosed >2026-10-09", "a `x` >2026-10-09", "see [[Note >2026-10-09]] b",
    "see [[Note >2026-10-09]] >2026-10-10", "see ![[pic >2026-10-09.png]]", "see [the >2026-10-09 doc](https://x.y/ >2026-10-08) b",
    "[ ] >2026-10-09", "Café ☕️ >2026-10-09", "🥛 @[[Ünï]] >2026-10-09 x", ">2026-10-09",
    "[a [b] >2026-10-09 c](https://x.y) d", "[a [b] >2026-10-09 c][ref] d", "[text >2026-10-09][ref] >2026-10-10",
    "[a [b](u) @[[A]] c](https://x.y) @[[B]]", "[a \\] >2026-10-09 b](https://x.y)", "[url](https://x.y/(a) >2026-10-09) z",
    "[a [b] >2026-10-09 c] d", "[x] >2026-10-09", "a  >2026-10-09  b", "a\t >2026-10-09", ">2026-10-09  b",
    "see [[Note]] @[[A]] >2026-10-09", "plain", "Call >2026-10-09. Then @[[A]],", "a >2026-10-09>2026-10-10",
]

/// Link forms the editor's parser reads differently: it counts an attribute in a reference link's text (`[t][ref]`), after an
/// escaped `]` in link text, and inside a url with nested parentheses. Core follows `docs/file-format.md`: links hold none.
private let editorDiffers = [
    "[a [b] >2026-10-09 c][ref] d", "[text >2026-10-09][ref] >2026-10-10", "[a \\] >2026-10-09 b](https://x.y)",
    "[url](https://x.y/(a) >2026-10-09) z",
]

private func readings(_ text: String) -> (core: (String?, String?), editor: (String?, String?))? {
    guard let task = MarkdownFacts.scan("- [ ] " + text + "\n").tasks.first else { return nil }
    let found = InlineAttributes.parse(task.text)
    return ((found.due?.date.description, found.parent?.title),
            (task.attributes.first { $0.kind == .due }?.value, task.attributes.first { $0.kind == .parent }?.value))
}

@Test func coreAndTheEditorReadTheSameAttributes() {
    var disagreements: [String] = []
    for text in specLines + coreTexts where !editorDiffers.contains(text) {
        guard let (core, editor) = readings(text) else { disagreements.append("\(text.debugDescription): no task"); continue }
        if core != editor { disagreements.append("\(text.debugDescription): core \(core), editor \(editor)") }
    }
    #expect(disagreements.isEmpty, "\(disagreements.joined(separator: "\n"))")
}

@Test func coreReadsNoAttributesInTheLinksTheEditorReadsDifferently() {
    for text in editorDiffers {
        let found = readings(text)?.core
        #expect(found?.0 == nil || text.hasSuffix(">2026-10-10"), "\(text)")
        #expect(found?.1 == nil)
    }
}
