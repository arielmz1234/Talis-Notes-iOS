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

  private func open(_ app: XCUIApplication, _ title: String) {
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

/// English labels the tests tap.
enum L10n {
  static let exportPDF = "Export PDF"
}
