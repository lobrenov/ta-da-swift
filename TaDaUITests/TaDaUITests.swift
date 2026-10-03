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
        app.typeKey("l", modifierFlags: .command)
        app.typeText("Second")
        XCTAssertEqual(body.value as? String, "- [ ] First line.\n- [ ] Second\n")

        app.typeKey("z", modifierFlags: .command)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(body.value as? String, "- [ ] First line.\n", "typing and each Add Subtask undo on their own")
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
