import Testing
@testable import TaDaCore

private func reminder(_ title: String, _ due: String?) -> ExternalReminder {
    ExternalReminder(identifier: title, title: title, due: due.flatMap(LocalDate.init), color: "#FF9500")
}

private let today = LocalDate("2026-10-14")!

@Test func todayHoldsOverdueAndDueTodayReminders() {
    #expect(reminder("Overdue", "2026-10-10").isInToday(today: today))
    #expect(reminder("Overdue", "2026-10-10").isOverdue(today: today))
    #expect(reminder("Due", "2026-10-14").isInToday(today: today))
    #expect(!reminder("Due", "2026-10-14").isOverdue(today: today))
    #expect(!reminder("Later", "2026-10-15").isInToday(today: today))
}

@Test func upcomingPutsRemindersOnTheirDueDateAfterToday() {
    #expect(reminder("Later", "2026-10-15").upcomingDate(after: today) == LocalDate("2026-10-15"))
    #expect(reminder("Due", "2026-10-14").upcomingDate(after: today) == nil)
    #expect(reminder("Overdue", "2026-10-01").upcomingDate(after: today) == nil)
}

@Test func undatedRemindersNeverShow() {
    let undated = reminder("Someday", nil)
    #expect(!undated.isInToday(today: today))
    #expect(!undated.isOverdue(today: today))
    #expect(undated.upcomingDate(after: today) == nil)
    #expect(ExternalReminder.today([undated], today: today).isEmpty)
    #expect(ExternalReminder.upcoming([undated], after: today).isEmpty)
}

@Test func remindersSortByDueDateThenTitle() {
    let reminders = [reminder("b", "2026-10-14"), reminder("Call", "2026-10-12"), reminder("a", "2026-10-14"),
                     reminder("Next", "2026-10-16"), reminder("Also next", "2026-10-16"), reminder("Soon", "2026-10-15")]
    #expect(ExternalReminder.today(reminders, today: today).map(\.title) == ["Call", "a", "b"])
    let upcoming = ExternalReminder.upcoming(reminders, after: today)
    #expect(upcoming.keys.sorted() == [LocalDate("2026-10-15")!, LocalDate("2026-10-16")!])
    #expect(upcoming[LocalDate("2026-10-16")!]?.map(\.title) == ["Also next", "Next"])
}
