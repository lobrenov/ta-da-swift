import Testing
import TaDaCore
@testable import TaDa

@MainActor @Suite struct DeadlineLabelTests {
    private let today = LocalDate("2026-10-21")!

    @Test func readsDaysLeftAndLate() {
        #expect(LocalDate("2026-10-21")!.deadlineLabel(today: today) == "Today")
        #expect(LocalDate("2026-10-22")!.deadlineLabel(today: today) == "1 day left")
        #expect(LocalDate("2026-10-26")!.deadlineLabel(today: today) == "5 days left")
        #expect(LocalDate("2026-10-20")!.deadlineLabel(today: today) == "1 day late")
        #expect(LocalDate("2026-10-11")!.deadlineLabel(today: today) == "10 days late")
    }
}
