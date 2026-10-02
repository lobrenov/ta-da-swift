import Testing
@testable import TaDaCore

@Test func localDateParsesAndPrintsYYYYMMDD() throws {
    let date = try #require(LocalDate("2026-10-02"))
    #expect((date.year, date.month, date.day) == (2026, 10, 2))
    #expect(date.description == "2026-10-02")
}

@Test(arguments: [
    "", "2026-10-2", "2026/10/02", "2026-10-02T09:00", " 2026-10-02", "26-10-02",
    "2026-13-01", "2026-00-10", "2026-04-31", "2026-02-29", "1900-02-29", "0000-01-01", "２０２６-10-02",
])
func localDateRejects(_ text: String) {
    #expect(LocalDate(text) == nil)
}

@Test func localDateAcceptsLeapDays() {
    #expect(LocalDate("2028-02-29") != nil)
    #expect(LocalDate("2000-02-29") != nil)
}

@Test func localDatesOrderByDay() throws {
    let dates = ["2026-10-02", "2025-12-31", "2026-09-30", "2026-10-01"].compactMap(LocalDate.init)
    #expect(dates.sorted().map(\.description) == ["2025-12-31", "2026-09-30", "2026-10-01", "2026-10-02"])
}
