// Smoke tests through the real UI, on the throwaway folder `-uiTesting` sets up. They need the
// Accessibility permission for Xcode's test runner (System Settings ▸ Privacy & Security ▸ Accessibility).
import AppKit
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

    func testMovingTasksFromTheFileMenuAndWithTheShortcut() throws {
        let project = app.buttons["Project"]
        app.buttons["Alpha"].rightClick()
        app.buttons["Move"].click()
        app.buttons.matching(NSPredicate(format: "label == 'Website' AND value CONTAINS 'open'")).firstMatch.click()
        app.buttons["Alpha"].click()
        waitForTitle("Alpha")
        waitForValue(project, "value == 'Website'")

        app.typeKey("m", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["Loose tasks"].waitForExistence(timeout: 5), "⇧⌘M opens the move menu")
        app.buttons["Loose tasks"].click()
        waitForValue(project, "value == 'None'")

        XCUIElement.perform(withKeyModifiers: .shift) { app.buttons["Beta"].click() }
        XCTAssertTrue(app.staticTexts["2 tasks selected"].waitForExistence(timeout: 5))
        app.typeKey("m", modifierFlags: [.command, .shift])
        app.typeText("Web")
        app.typeKey(.return, modifierFlags: [])
        for name in ["Beta", "Alpha"] {
            app.buttons[name].click()
            waitForTitle(name)
            waitForValue(project, "value == 'Website'")
        }
    }

    func testDraggingATaskOntoASidebarProject() throws {
        let website = app.buttons.matching(NSPredicate(format: "label == 'Website'")).firstMatch
        app.buttons["Alpha"].press(forDuration: 0.5, thenDragTo: website)
        XCTAssertTrue(app.buttons["Website, 1"].waitForExistence(timeout: 5), "the drop links Alpha to Website")
        app.buttons["Alpha"].click()
        waitForTitle("Alpha")
        waitForValue(app.buttons["Project"], "value == 'Website'")

        app.buttons["Alpha"].press(forDuration: 0.5,
                                   thenDragTo: app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Loose tasks'")).firstMatch)
        waitForValue(app.buttons["Project"], "value == 'None'")
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

    func testTheProjectPagesTasksTableEditsInPlace() throws {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Roadmap'")).firstMatch.click()
        app.buttons["Open project file"].click()
        let newTask = app.buttons["New linked task"]
        XCTAssertTrue(newTask.waitForExistence(timeout: 5), "the project page is open")
        newTask.click()

        let titleField = app.textFields.matching(identifier: "linked-task-title").firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "the new row's title is ready to type")
        waitForValue(titleField, "isHittable == true")
        waitForValue(titleField, "hasKeyboardFocus == true")
        app.typeText("Ship it")
        app.typeKey(.return, modifierFlags: [])
        let shipIt = app.groups["Ship it"]
        XCTAssertTrue(shipIt.waitForExistence(timeout: 5), "Return renames the new task in its row")
        XCTAssertTrue(newTask.exists, "and the project page stays open")

        // The rename sorts the row to the top of the table, which can be under the toolbar.
        let top = app.windows.firstMatch.frame.minY + 120
        let lower = app.groups["Step 10"]
        for _ in 0..<5 where shipIt.frame.minY < top { lower.scroll(byDeltaX: 0, deltaY: 120) }
        shipIt.buttons["status"].click()
        XCTAssertTrue(app.buttons["Doing"].waitForExistence(timeout: 5), "the status cell opens the status menu")
        app.buttons["Doing"].click()
        waitForValue(shipIt.buttons["status"], "value == 'Doing'")

        shipIt.buttons["dueDate"].click()
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        waitForValue(shipIt.buttons["dueDate"], "value != 'none'")

        shipIt.buttons["title"].click()
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "clicking the title edits it")
        waitForValue(titleField, "hasKeyboardFocus == true")
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Shipped")
        app.staticTexts["Tasks"].click()
        let shipped = app.groups["Shipped"]
        XCTAssertTrue(shipped.waitForExistence(timeout: 5), "a click away renames it")

        shipped.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).click()
        waitForTitle("Shipped")
        XCTAssertTrue(app.buttons["Open project file"].exists, "the rest of the row opens the task beside the project's browser")
    }

    func testCompleteSelectedTask() throws {
        app.buttons["Alpha"].click()
        waitForTitle("Alpha")
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Mark not done: Alpha"].waitForExistence(timeout: 5))
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Complete: Alpha"].waitForExistence(timeout: 5))
    }

    func testPastingAnImageEmbedsIt() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        let png = try XCTUnwrap(bitmap?.representation(using: .png, properties: [:]))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)

        app.buttons["Alpha"].click()
        waitForTitle("Alpha")
        body.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
        let embed = NSPredicate(format: "value MATCHES %@", #"(?s)First line\.\n+!\[\[Pasted image \d{14}\.png\]\]\n*"#)
        let pasted = XCTNSPredicateExpectation(predicate: embed, object: body)
        XCTAssertEqual(XCTWaiter.wait(for: [pasted], timeout: 5), .completed, "⌘V saves the image and embeds it on a line of its own")
    }
}
