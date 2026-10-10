import Testing
@testable import TaDaCore

@Test func linkSearchRanksTitleStartThenWordStartThenAnywhere() {
    let titles = ["Draft the UAT scripts", "Squat rack", "uat-flow.png", "UAT sign-off", "Kombi service history"]
    #expect(LinkSearch.rank(titles, query: "uat") { $0 } == ["uat-flow.png", "UAT sign-off", "Draft the UAT scripts", "Squat rack"])
    #expect(LinkSearch.rank(titles, query: "flow") { $0 } == ["uat-flow.png"])
    #expect(LinkSearch.rank(titles, query: "xyz") { $0 }.isEmpty)
}

@Test func linkSearchKeepsTheOrderForAnEmptyQueryAndIgnoresAccents() {
    #expect(LinkSearch.rank(["b", "a"], query: " ") { $0 } == ["b", "a"])
    #expect(LinkSearch.rank(["Café plans"], query: "cafe") { $0 } == ["Café plans"])
}
