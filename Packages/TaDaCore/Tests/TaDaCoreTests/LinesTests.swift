import Testing
@testable import TaDaCore

@Test(arguments: ["", "a", "a\n", "a\nb", "a\r\nb\r\n", "\n\n", "Ünï\r\ncödé 🙂\n"])
func linesRoundTrip(_ text: String) {
    #expect(Lines(text).text == text)
}

@Test func linesDetectTheFileEnding() {
    #expect(Lines("a\r\nb\n").ending == "\r\n")
    #expect(Lines("a\nb\r\n").ending == "\n")
    #expect(Lines("no newline").ending == "\n")
    #expect(Lines.content("abc\r\n") == "abc")
    #expect(Lines.content("abc\n") == "abc")
    #expect(Lines.content("abc") == "abc")
}
