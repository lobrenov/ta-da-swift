// Smoke tests through the real UI, on the throwaway folder `-uiTesting` sets up. They need the
// Accessibility permission for Xcode's test runner (System Settings ▸ Privacy & Security ▸ Accessibility).
import XCTest

@MainActor
final class TaDaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.buttons["Alpha"].waitForExistence(timeout: 10), "the test folder's tasks are listed")
    }

    private var title: XCUIElement { app.textViews["Title"].exists ? app.textViews["Title"] : app.textFields["Title"] }
    /// The label sits on the editor's scroll view.
    private var body: XCUIElement { app.scrollViews["Body"].textViews.firstMatch }

    private func waitForTitle(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let match = NSPredicate(format: "value == %@", expected)
        let found = XCTNSPredicateExpectation(predicate: match, object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [found], timeout: 5), .completed, "title is \(expected)", file: file, line: line)
    }

    func testDeletingAndRestoringFiles() throws {
        app.buttons["Alpha"].rightClick()
        app.buttons["Delete"].click()
        XCTAssertTrue(app.buttons["Alpha"].waitForNonExistence(timeout: 5), "the file menu's Delete moves Alpha to the trash")

        app.buttons["Beta"].click()
        waitForTitle("Beta")
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.buttons["Beta"].waitForNonExistence(timeout: 5), "⌫ moves the selected file to the trash")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Trash'")).firstMatch.click()
        let alpha = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Alpha'")).firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.rightClick()
        app.buttons["Restore"].click()
        XCTAssertTrue(alpha.waitForNonExistence(timeout: 5), "Restore takes Alpha out of the trash")
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Alpha"].waitForExistence(timeout: 5), "and back into Today")
    }

    func testArrowKeysMoveThroughTodayButNotWhileEditing() throws {
        app.typeKey(.downArrow, modifierFlags: [])
        waitForTitle("Alpha")
        app.typeKey(.downArrow, modifierFlags: [])
        waitForTitle("Beta")
        app.typeKey(.upArrow, modifierFlags: [])
        waitForTitle("Alpha")

        body.click()
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        waitForTitle("Alpha")

        app.buttons["Beta"].click()
        waitForTitle("Beta")
        app.typeKey(.upArrow, modifierFlags: [])
        waitForTitle("Alpha")
    }

    func testAddSubtaskAndUndo() throws {
        app.buttons["Alpha"].click()
        waitForTitle("Alpha")
        body.click()
        app.typeKey(.upArrow, modifierFlags: .command)
        app.typeKey("l", modifierFlags: .command)
        XCTAssertEqual(body.value as? String, "- [ ] First line.\n")
        app.typeText("Do ")
        XCTAssertEqual(body.value as? String, "- [ ] Do First line.\n")
        app.typeKey("l", modifierFlags: .command)
        XCTAssertEqual(body.value as? String, "- [x] Do First line.\n", "⌘L on a subtask completes it")
        app.typeKey("l", modifierFlags: .command)
        XCTAssertEqual(body.value as? String, "- [ ] Do First line.\n", "and again reopens it")

        app.typeKey("z", modifierFlags: .command)
        app.typeKey("z", modifierFlags: .command)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(body.value as? String, "- [ ] First line.\n", "typing and each ⌘L undo on their own")
    }

    func testClosingTheWindowRightAfterTypingSavesTheEdit() throws {
        app.buttons["Alpha"].click()
        waitForTitle("Alpha")
        body.click()
        app.typeKey(.upArrow, modifierFlags: .command)
        app.typeText("Saved. ")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "closing the only window quits")

        app.launchArguments = ["-uiTesting", "-uiTestingRelaunch"]
        app.launch()
        app.buttons["Alpha"].click()
        waitForTitle("Alpha")
        XCTAssertEqual(body.value as? String, "Saved. First line.\n")
        XCTAssertFalse(app.buttons["Alpha (unsaved edits)"].exists)
    }

    private func waitForValue(_ element: XCUIElement, _ format: String, file: StaticString = #filePath, line: UInt = #line) {
        let found = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [found], timeout: 5), .completed, "\(element.label): \(format)", file: file, line: line)
    }

    func testPropertyChipsPickFromTheirMenusWithTheKeyboard() throws {
        app.buttons["Alpha"].click()
        waitForTitle("Alpha")

        let status = app.buttons["Status"]
        status.click()
        XCTAssertTrue(app.buttons["Doing"].waitForExistence(timeout: 5), "the status menu lists the statuses")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        waitForValue(status, "value == 'Doing'")
        status.click()
        app.typeKey("b", modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        waitForValue(status, "value == 'Blocked'")

        let project = app.buttons["Project"]
        project.click()
        app.typeText("Launch")
        XCTAssertTrue(app.buttons["New project “Launch”"].waitForExistence(timeout: 5), "typing offers a project by that name")
        app.typeKey(.return, modifierFlags: [])
        waitForValue(project, "value == 'Launch'")

        let deadline = app.buttons["Deadline"]
        deadline.click()
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        waitForValue(deadline, "value != 'None'")
    }

    func testAddSubtaskIsOffUnlessAnEditorHasTheKeyboard() throws {
        app.buttons["Alpha"].click()
        waitForTitle("Alpha")
        let taskMenu = app.menuBars.menuBarItems["Task"]
        taskMenu.click()
        XCTAssertFalse(app.menuItems["Add Subtask"].isEnabled, "the list has the keyboard")
        app.typeKey(.escape, modifierFlags: [])

        body.click()
        taskMenu.click()
        XCTAssertTrue(app.menuItems["Add Subtask"].isEnabled, "the editor has the keyboard")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testCompleteSelectedTask() throws {
        app.buttons["Alpha"].click()
        waitForTitle("Alpha")
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Mark not done: Alpha"].waitForExistence(timeout: 5))
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Complete: Alpha"].waitForExistence(timeout: 5))
    }
}
