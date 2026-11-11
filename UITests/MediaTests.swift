import XCTest

/// Pictures, PDFs, voice memos, the camera and export.
@MainActor
final class MediaTests: ShotCase {

  private func openSeededPDF(_ app: XCUIApplication) -> Bool {
    let pdf = app.descendants(matching: .any)["notebook-Lecture slides"].firstMatch
    guard pdf.waitForExistence(timeout: 5) else { return false }
    pdf.tap()
    settle()
    return true
  }

  func testPdfOpens() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch()
    settle()
    XCTAssertTrue(openSeededPDF(app), "the seeded PDF is in the library")
    shot("m1-pdf")
  }

  func open(_ app: XCUIApplication, _ title: String) {
    let card = app.descendants(matching: .any)["notebook-\(title)"].firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 5), "\(title) is in the library")
    card.tap()
    settle()
    if app.buttons["write"].exists {
      app.buttons["write"].firstMatch.tap()
      settle()
    }
  }

  private func waitForSize(_ app: XCUIApplication) {
    let size = app.staticTexts["export-size"].firstMatch
    let made = NSPredicate(format: "label CONTAINS 'KB' OR label CONTAINS 'MB' OR label CONTAINS '1 KB'")
    _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: made, object: size)], timeout: 20)
  }

  /// Export: the notebook's pages (exact A4), then one long page; the app keeps each PDF in its
  /// temporary folder under -uitest so the run can render them.
  func testExport() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch()
    settle()
    open(app, "Lab report")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
      .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55)))
    showTool(app, "tool-keyboard")
    app.buttons["tool-keyboard"].firstMatch.tap()
    if app.keyboards.firstMatch.waitForExistence(timeout: 3) { app.typeText("Typed text stays text") }
    showTool(app, "tool-lasso")
    app.buttons["tool-lasso"].firstMatch.tap()
    settle()
    app.buttons["more"].firstMatch.tap()
    settle()
    app.buttons[L10n.exportPDF].firstMatch.tap()
    settle()
    waitForSize(app)
    shot("e1-export")
    app.descendants(matching: .any)["One long page"].firstMatch.tap()
    waitForSize(app)
    shot("e2-export-long")
  }
}

extension MediaTests {
  /// Insert: the menu, a picture in the middle of the view, then PDF pages after the last page.
  func testInsert() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch(["-fakePickers"])
    settle()
    open(app, "Truss problems")
    showTool(app, "tool-insert")
    app.buttons["tool-insert"].firstMatch.tap()
    settle()
    shot("i1-insert-menu")
    app.buttons["insert-picture"].firstMatch.tap()
    settle()
    shot("i2-picture")
    showTool(app, "tool-insert")
    app.buttons["tool-insert"].firstMatch.tap()
    settle()
    app.buttons["insert-pdf"].firstMatch.tap()
    Thread.sleep(forTimeInterval: 0.4)
    shot("i3-pdf-adding")
    settle()
    settle()
    shot("i4-pdf-pages")
    app.buttons["Undo"].firstMatch.tap()
    settle()
    app.swipeDown()
    app.swipeDown()
    settle()
    shot("i5-undone")
  }
}

extension MediaTests {
  /// Voice memos: record (the simulator's microphone), Done, Add beside the page, open, play, then
  /// carry it across to the page's other side.
  func testVoiceMemo() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch()
    addUIInterruptionMonitor(withDescription: "microphone") { alert in
      for label in ["Allow", "OK"] where alert.buttons[label].exists {
        alert.buttons[label].tap()
        return true
      }
      return false
    }
    settle()
    open(app, "Fluid mechanics")
    showTool(app, "tool-voice")
    app.buttons["tool-voice"].firstMatch.tap()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let allow = springboard.buttons["Allow"]
    if allow.waitForExistence(timeout: 2) { allow.tap() }
    app.tap()
    Thread.sleep(forTimeInterval: 2.5)
    shot("v1-recording")
    app.buttons["memo-done"].firstMatch.tap()
    settle()
    shot("v2-draft")
    app.buttons["memo-add"].firstMatch.tap()
    settle()
    shot("v3-added")
    let memo = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Open voice memo'")).firstMatch
    XCTAssertTrue(memo.waitForExistence(timeout: 3), "the memo sits beside the page")
    memo.tap()
    settle()
    shot("v4-open")
    app.buttons["memo-play"].firstMatch.tap()
    Thread.sleep(forTimeInterval: 0.8)
    shot("v5-playing")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
    settle()
    let at = memo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    at.press(forDuration: 0.7, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.6)), withVelocity: .slow, thenHoldForDuration: 0.3)
    settle()
    shot("v6-moved")
  }
}

/// English labels the tests tap.
enum L10n {
  static let exportPDF = "Export PDF"
}
