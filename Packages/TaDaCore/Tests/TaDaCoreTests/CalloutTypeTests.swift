import Testing
@testable import TaDaCore

@Test func calloutTypesReadByNameOrAliasIgnoringCase() {
    #expect(CalloutType(named: "warning") == .warning)
    #expect(CalloutType(named: "FAQ") == .question)
    #expect(CalloutType(named: "Tldr") == .abstract)
    #expect(CalloutType(named: "recipe") == nil)
    #expect(CalloutType.allCases.count == 13)
    #expect(CalloutType.abstract.title == "Abstract")
}
