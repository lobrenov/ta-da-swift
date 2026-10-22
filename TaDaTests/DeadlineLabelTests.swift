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

    @Test func rowLabelSummarises() {
        // Wednesday 21 Oct 2026
        #expect(today.rowLabel(today: today) == "Today")
        #expect(LocalDate("2026-10-22")!.rowLabel(today: today) == "Thu")
        #expect(LocalDate("2026-10-27")!.rowLabel(today: today) == "Tue")
        #expect(LocalDate("2026-10-28")!.rowLabel(today: today) == "28 Oct")
        #expect(LocalDate("2026-10-29")!.rowLabel(today: today) == "29 Oct")
        #expect(LocalDate("2026-10-19")!.rowLabel(today: today) == "19 Oct")
        #expect(LocalDate("2027-10-29")!.rowLabel(today: today) == "29 Oct 2027")
        #expect(LocalDate("2025-12-31")!.rowLabel(today: today) == "31 Dec 2025")
    }
}
