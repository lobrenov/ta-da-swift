import Testing
@testable import TaDaCore

@Test func statusReadsCaseInsensitively() {
    #expect(Status(reading: "Not Started") == .notStarted)
    #expect(Status(reading: "not started") == .notStarted)
    #expect(Status(reading: "DOING") == .doing)
    #expect(Status(reading: " done ") == .done)
    #expect(Status(reading: "blocked") == .blocked)
}

@Test func statusRejectsOtherValues() {
    #expect(Status(reading: "NotStarted") == nil)
    #expect(Status(reading: "In progress") == nil)
    #expect(Status(reading: "") == nil)
}

@Test func statusWritesCanonicalForms() {
    #expect(Status.allCases.map(\.rawValue) == ["Not Started", "Doing", "Done", "Blocked"])
}
