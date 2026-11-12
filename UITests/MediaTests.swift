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
    tapTool(app, "tool-keyboard")
    if app.keyboards.firstMatch.waitForExistence(timeout: 3) { app.typeText("Typed text stays text") }
    tapTool(app, "tool-lasso")
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
    tapTool(app, "tool-insert")
    settle()
    shot("i1-insert-menu")
    app.buttons["insert-picture"].firstMatch.tap()
    settle()
    shot("i2-picture")
    tapTool(app, "tool-insert")
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
    tapTool(app, "tool-voice")
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

extension MediaTests {
  /// A memo goes with its page: copied when the page is duplicated, moved when it's moved, gone
  /// when it's deleted, and back with undo.
  func testMemosFollowTheirPages() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch()
    settle()
    open(app, "Fluid mechanics")
    tapTool(app, "tool-voice")
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
    if allow.waitForExistence(timeout: 2) { allow.tap() }
    Thread.sleep(forTimeInterval: 2.5)
    app.buttons["memo-done"].firstMatch.tap()
    settle()
    app.buttons["memo-add"].firstMatch.tap()
    settle()
    let memos = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Open voice memo'"))
    XCTAssertEqual(memos.count, 1, "the memo sits beside page 1")
    let home = memos.firstMatch.frame
    func overview() {
      app.buttons.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ / [0-9]+")).firstMatch.tap()
      settle()
    }
    func closeOverview() {
      app.buttons["Done"].firstMatch.tap()
      settle()
    }
    // Duplicated with its page.
    overview()
    app.buttons["Add a page"].firstMatch.tap()
    settle()
    app.buttons["pages-select"].firstMatch.tap()
    app.buttons["Pick page 1"].firstMatch.tap()
    app.buttons["Duplicate"].firstMatch.tap()
    settle()
    closeOverview()
    shot("v7-memo-copied-with-its-page")
    XCTAssertEqual(memos.count, 2, "the page's copy has a copy of its memo")
    app.buttons["undo"].firstMatch.tap()
    settle()
    XCTAssertEqual(memos.count, 1, "undo takes the copy away again")
    // Moved with its page: page 1 dragged after page 2.
    overview()
    app.buttons["Look at page 1"].firstMatch.press(forDuration: 1.0, thenDragTo: app.buttons["Look at page 2"].firstMatch)
    settle()
    closeOverview()
    shot("v8-memo-moved-with-its-page")
    XCTAssertTrue(!memos.firstMatch.exists || memos.firstMatch.frame.minY > home.minY + 100, "the memo went down with its page")
    app.buttons["undo"].firstMatch.tap()
    settle()
    XCTAssertEqual(memos.firstMatch.frame.minY, home.minY, accuracy: 4, "undo brings the page and its memo back")
    // Deleted with its page.
    overview()
    app.buttons["Look at page 1"].firstMatch.tap()
    settle()
    app.buttons["Delete page"].firstMatch.tap()
    settle()
    let confirm = app.buttons.matching(NSPredicate(format: "label == 'Delete page'"))
    confirm.element(boundBy: confirm.count - 1).tap()
    Thread.sleep(forTimeInterval: 1.5)
    closeOverview()
    shot("v9-memo-gone-with-its-page")
    XCTAssertEqual(memos.count, 0, "the deleted page's memo went with it")
    app.buttons["undo"].firstMatch.tap()
    settle()
    XCTAssertEqual(memos.count, 1, "and comes back with it")
  }
}

extension MediaTests {
  /// The camera with a drawn photo of a tilted page (-cameraPicture; the simulator has no camera):
  /// the look step, Crop with the corners dragged onto the page (held, for the magnifier), Next,
  /// Document, then Save puts it on the page.
  func testCamera() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch(["-cameraPicture"])
    settle()
    open(app, "Exam revision")
    tapTool(app, "tool-insert")
    settle()
    app.buttons["insert-photo"].firstMatch.tap()
    settle()
    shot("c1-look")
    app.buttons["cam-Crop"].firstMatch.tap()
    settle()
    let tl = app.otherElements["corner-0"].firstMatch, br = app.otherElements["corner-2"].firstMatch
    XCTAssertTrue(tl.waitForExistence(timeout: 3), "the crop corners show")
    let a = tl.frame.center, b = br.frame.center
    func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
      app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: a.x + (b.x - a.x) * x, dy: a.y + (b.y - a.y) * y))
    }
    shot("c2-crop")
    let page: [(CGFloat, CGFloat)] = [(0.26, 0.113), (0.78, 0.167), (0.74, 0.92), (0.21, 0.86)]
    for (i, corner) in [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)].enumerated() {
      at(corner.0, corner.1).press(forDuration: 0.2, thenDragTo: at(page[i].0, page[i].1), withVelocity: .slow, thenHoldForDuration: i == 0 ? 4 : 0.1)
    }
    settle()
    shot("c4-cropped")
    app.buttons["cam-next"].firstMatch.tap()
    settle()
    app.descendants(matching: .any)["look-DOCUMENT"].firstMatch.tap()
    settle()
    settle()
    shot("c5-document")
    app.descendants(matching: .any)["look-BLACK_WHITE"].firstMatch.tap()
    settle()
    settle()
    shot("c6-bw")
    app.descendants(matching: .any)["look-DOCUMENT"].firstMatch.tap()
    settle()
    app.buttons["cam-save"].firstMatch.tap()
    settle()
    settle()
    shot("c7-on-page")
  }
}

extension CGRect {
  var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension MediaTests {
  /// + › Camera in the library: the photo becomes a Picture item, with the Adding pill and Open.
  func testAddingPill() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch(["-cameraPicture"])
    settle()
    app.buttons["add"].firstMatch.tap()
    XCTAssertTrue(app.buttons["add-camera"].waitForExistence(timeout: 8), "the + menu offers Camera")
    app.buttons["add-camera"].firstMatch.tap()
    settle()
    app.buttons["cam-save"].firstMatch.tap()
    let words = app.staticTexts["adding-words"].firstMatch
    XCTAssertTrue(words.waitForExistence(timeout: 5), "the pill shows")
    shot("a1-adding")
    XCTAssertTrue(app.buttons["adding-open"].waitForExistence(timeout: 8), "Added, with Open")
    shot("a2-added")
    app.buttons["adding-open"].firstMatch.tap()
    settle()
    shot("a3-opened")
  }
}

extension MediaTests {
  /// A PDF opened with the app from another one (-openURL stands in for iOS handing it over): a draft
  /// just for looking, with Save; Back asks; Save makes it one of hers and the toolbars come in.
  func testPdfFromAnotherApp() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch(["-openURL", "Lecture slides.pdf"])
    XCTAssertTrue(app.buttons["draft-save"].waitForExistence(timeout: 8), "the draft viewer opens with Save")
    settle()
    shot("o1-draft")
    app.buttons["back"].firstMatch.tap()
    settle()
    shot("o2-leave")
    app.buttons["Keep looking"].firstMatch.tap()
    settle()
    app.buttons["draft-save"].firstMatch.tap()
    settle()
    shot("o3-save")
    app.buttons["draft-save-confirm"].firstMatch.tap()
    settle()
    shot("o4-saved")
    app.buttons["back"].firstMatch.tap()
    settle()
    shot("o5-library")
  }
}

extension MediaTests {
  /// A picture and some text dropped on the page (-fakeDrop hands the canvas what a drag from another
  /// app would): the picture lands where it was dropped, the text as a text box.
  func testDrop() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch(["-fakeDrop"])
    settle()
    open(app, "Truss problems")
    Thread.sleep(forTimeInterval: 3)
    shot("d1-dropped")
  }
}

extension MediaTests {
  /// Cropping a picture just added: Crop beside it, the frame's left side and bottom-right corner
  /// dragged in, Done; then Crop again and Reset brings the whole picture back.
  func testCropPicture() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch(["-fakePickers"])
    settle()
    open(app, "Week 3 lecture")
    tapTool(app, "tool-insert")
    settle()
    app.buttons["insert-picture"].firstMatch.tap()
    settle()
    shot("k1-offer")
    app.buttons["selection-crop"].firstMatch.tap()
    settle()
    shot("k2-cropping")
    let f = app.descendants(matching: .any)["crop-frame"].firstMatch.frame
    let origin = app.coordinate(withNormalizedOffset: .zero)
    func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { origin.withOffset(CGVector(dx: x, dy: y)) }
    at(f.minX, f.midY).press(forDuration: 0.1, thenDragTo: at(f.minX + f.width * 0.3, f.midY), withVelocity: .slow, thenHoldForDuration: 0.1)
    at(f.maxX, f.maxY).press(forDuration: 0.1, thenDragTo: at(f.maxX - f.width * 0.1, f.maxY - f.height * 0.25), withVelocity: .slow, thenHoldForDuration: 0.1)
    settle()
    shot("k3-frame")
    app.buttons["crop-done"].firstMatch.tap()
    settle()
    shot("k4-cropped")
  }
}

/// English labels the tests tap.
enum L10n {
  static let exportPDF = "Export PDF"
}
