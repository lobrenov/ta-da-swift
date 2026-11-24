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

@Test func linkSearchByBytesAgreesWithFoundation() {
    let names = ["Kombi service", "x a b", "a-b", "_a b", "Draft the UAT", "uat", "UAT sign-off", "ab", "Café", "", "a", "b a b"]
    for query in ["a", "a b", "a-b", "uat", "UA", "b", "ab", "e", "é", "-", "sign-off"] {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        func expected(_ name: String) -> Int? {
            if name.range(of: query, options: options.union(.anchored)) != nil { return 0 }
            if name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
                .contains(where: { $0.range(of: query, options: options.union(.anchored)) != nil }) { return 1 }
            return name.range(of: query, options: options) != nil ? 2 : nil
        }
        let want = names.compactMap { name in expected(name).map { (rank: $0, name: name) } }.sorted { $0.rank < $1.rank }.map(\.name)
        #expect(LinkSearch.rank(names, query: query) { $0 }.sorted() == want.sorted(), "\(query)")
        #expect(LinkSearch.rank(names, query: query) { $0 }.map { expected($0)! } == want.map { expected($0)! }, "\(query)")
    }
}

@Test func linkSearchLimitKeepsTheFirstOfTheFullOrder() {
    let names = (0..<300).map { "Task \(($0 * 37) % 300) re\($0 % 5)" } + ["Re one", "re-two", "Zero"]
    let full = LinkSearch.rank(names, query: "re", name: { $0 }, then: <)
    for limit in [1, 7, 50, 400] {
        #expect(LinkSearch.rank(names, query: "re", name: { $0 }, then: <, limit: limit) == Array(full.prefix(limit)), "\(limit)")
    }
}

@Test func linkSearchOrdersAnEmptyQueryByThen() {
    #expect(LinkSearch.rank(["b", "c", "a"], query: " ", name: { $0 }, then: <) == ["a", "b", "c"])
    #expect(LinkSearch.rank(["b", "c", "a"], query: "", name: { $0 }, then: <, limit: 2) == ["a", "b"])
}
