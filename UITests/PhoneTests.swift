import XCTest

/// The notebook on a phone (Android's items 67 and 73): the folded tools, every panel, menu and card,
/// with nothing cut off by the screen's edges. The same walk runs on the iPad.
@MainActor
final class PhoneTests: ShotCase {
  private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

  private func openNewNotebook(_ extra: [String] = []) -> XCUIApplication {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
    let app = launch(extra)
    XCTAssertTrue(app.buttons["add"].firstMatch.waitForExistence(timeout: 20))
    settle()
    app.buttons["add"].firstMatch.tap()
    XCTAssertTrue(app.buttons["add-notebook"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["add-notebook"].firstMatch.tap()
    XCTAssertTrue(app.buttons["create"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["create"].firstMatch.tap()
    XCTAssertTrue(app.buttons["back"].firstMatch.waitForExistence(timeout: 10))
    settle()
    if app.buttons["write"].exists {
      app.buttons["write"].firstMatch.tap()
      settle()
    }
    return app
  }

  private func at(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
    app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
  }

  private func drag(_ app: XCUIApplication, _ from: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat)) {
    at(app, from.0, from.1).press(forDuration: 0.05, thenDragTo: at(app, to.0, to.1), withVelocity: .slow, thenHoldForDuration: 0.05)
    settle()
  }

  private func tool(_ app: XCUIApplication, _ id: String) {
    tapTool(app, id)
    settle()
  }

  /// A stop on the walk: a shot, and nothing off the screen.
  private func stop(_ app: XCUIApplication, _ name: String) {
    shot(name)
    assertAllOnScreen(app, name)
  }

  static let tools = ["eraser", "lasso", "fill", "laser", "shapes", "insert", "voice", "keyboard"]

  func testToolsRow() {
    let app = openNewNotebook()
    stop(app, "ph-a1-toolbar")
    guard app.buttons["tools-button"].exists else { return }
    app.buttons["tools-button"].firstMatch.tap()
    settle()
    stop(app, "ph-a2-tools-open")
    let screen = app.windows.firstMatch.frame
    let frames = Self.tools.map { app.buttons["tool-\($0)"].firstMatch.frame }
    for (name, f) in zip(Self.tools, frames) {
      XCTAssertTrue(f.width > 0 && screen.contains(f), "\(name) is on the screen, at \(f)")
    }
    XCTAssertEqual(frames.first!.minX + frames.last!.maxX, screen.width, accuracy: 3, "the tools are centred under the pens")
    XCTAssertGreaterThan(frames.first!.minY, app.buttons["pen-p1"].firstMatch.frame.maxY, "in a bar of their own below the pens")
    // Choosing a tool folds them away; its button shows the tool in use.
    app.buttons["tool-eraser"].firstMatch.tap()
    settle()
    XCTAssertFalse(app.buttons["tool-lasso"].exists, "choosing a tool folds the tools away")
    stop(app, "ph-a3-eraser-chosen")
    // Opened again and the eraser tapped again: its panel, under the pens.
    tool(app, "tool-eraser")
    XCTAssertTrue(app.buttons["Precise"].waitForExistence(timeout: 3), "the eraser's panel")
    XCTAssertFalse(app.buttons["tool-lasso"].exists)
    stop(app, "ph-a4-eraser-panel")
    // The tools button closes the panel as it opens the tools.
    app.buttons["tools-button"].firstMatch.tap()
    settle()
    XCTAssertFalse(app.buttons["Precise"].exists, "opening the tools closes the panel")
    XCTAssertTrue(app.buttons["tool-lasso"].exists)
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
  }

  /// A narrower phone than the simulator's: the tools come in pages, with an arrow to the next.
  func testToolsPageOnANarrowPhone() {
    let app = openNewNotebook(["-toolsRoom", "300"])
    guard app.buttons["tools-button"].exists else { return }
    app.buttons["tools-button"].firstMatch.tap()
    settle()
    stop(app, "ph-b1-first-tools")
    XCTAssertTrue(app.buttons["tool-eraser"].exists && app.buttons["tool-insert"].exists, "six tools fit")
    XCTAssertFalse(app.buttons["tool-keyboard"].exists, "the rest are on the next page")
    app.buttons["tools-page"].firstMatch.tap()
    settle()
    stop(app, "ph-b2-more-tools")
    XCTAssertTrue(app.buttons["tool-keyboard"].exists && app.buttons["tool-voice"].exists)
    XCTAssertFalse(app.buttons["tool-eraser"].exists)
    app.buttons["tools-page"].firstMatch.tap()
    settle()
    XCTAssertTrue(app.buttons["tool-eraser"].exists, "the arrow goes back to the first tools")
    // The tool in use brings its page when the tools open.
    app.buttons["tool-laser"].firstMatch.tap()
    settle()
    app.buttons["tools-button"].firstMatch.tap()
    settle()
    XCTAssertTrue(app.buttons["tool-laser"].exists)
    app.buttons["pen-p1"].firstMatch.tap()
  }

  /// The panel of the tool in use, opened from its button.
  private func panel(_ app: XCUIApplication, _ id: String, shows probe: String) {
    tool(app, id)
    if !app.descendants(matching: .any)[probe].firstMatch.waitForExistence(timeout: 1.5) { tool(app, id) }
    XCTAssertTrue(app.descendants(matching: .any)[probe].firstMatch.waitForExistence(timeout: 3), "\(id)'s panel shows \(probe)")
  }

  private func scrollPanel(_ app: XCUIApplication) {
    at(app, 0.5, 0.7).press(forDuration: 0.05, thenDragTo: at(app, 0.5, 0.3))
    settle()
  }

  func testPanels() {
    let app = openNewNotebook()
    app.buttons["pen-p1"].firstMatch.tap()
    if !app.buttons["Add a pen"].waitForExistence(timeout: 1.5) { app.buttons["pen-p1"].firstMatch.tap() }
    settle()
    stop(app, "ph-c1-pen-panel")
    scrollPanel(app)
    stop(app, "ph-c2-pen-panel-scrolled")
    app.buttons["pen-p5"].firstMatch.tap()
    settle()
    app.buttons["pen-p5"].firstMatch.tap()
    settle()
    stop(app, "ph-c3-highlighter-panel")
    panel(app, "tool-lasso", shows: "lasso-screenshot")
    stop(app, "ph-c4-select-panel")
    panel(app, "tool-fill", shows: "no-fill")
    stop(app, "ph-c5-fill-panel")
    panel(app, "tool-shapes", shows: "more-shapes")
    stop(app, "ph-c6-shapes-panel")
    let tabs = app.buttons.matching(identifier: "shapes-tabs")
    tabs.element(boundBy: 1).tap()
    settle()
    stop(app, "ph-c7-shapes-style")
    scrollPanel(app)
    stop(app, "ph-c8-shapes-style-scrolled")
    tabs.element(boundBy: 0).tap()
    settle()
    app.buttons["more-shapes"].firstMatch.tap()
    XCTAssertTrue(app.buttons["packs-done"].waitForExistence(timeout: 3), "the subjects' shapes")
    settle()
    stop(app, "ph-c9-more-shapes")
    app.descendants(matching: .any)["subject-electrical"].firstMatch.tap()
    settle()
    stop(app, "ph-c10-a-subject")
    app.buttons["packs-done"].firstMatch.tap()
    settle()
    app.buttons["pen-p1"].firstMatch.tap()
  }

  func testSelectionMenu() {
    let app = openNewNotebook()
    drag(app, (0.30, 0.44), (0.60, 0.45))
    drag(app, (0.30, 0.50), (0.60, 0.49))
    tool(app, "tool-lasso")
    drag(app, (0.45, 0.38), (0.48, 0.56))
    XCTAssertTrue(app.buttons["selection-delete"].waitForExistence(timeout: 3), "picked up")
    stop(app, "ph-d1-selection-menu")
    app.buttons["selection-more"].firstMatch.tap()
    settle()
    shot("ph-d2-menu-opened")
    let row = app.scrollViews["selection-row"].firstMatch
    func reach(_ id: String) -> XCUIElement {
      let b = app.buttons[id].firstMatch
      var tries = 0
      while b.exists, !b.isHittable, row.exists, tries < 4 {
        row.swipeLeft()
        tries += 1
      }
      return b
    }
    reach("selection-colour").tap()
    settle()
    stop(app, "ph-d3-menu-colours")
    reach("selection-thickness").tap()
    settle()
    stop(app, "ph-d4-menu-thickness")
    XCTAssertTrue(reach("save-as-shape").isHittable, "the last button is reached by scrolling")
    reach("save-as-shape").tap()
    settle()
    stop(app, "ph-d5-save-shape")
    at(app, 0.5, 0.12).tap()
    settle()
    // A shape just drawn, with its dots and chips.
    panel(app, "tool-shapes", shows: "more-shapes")
    app.buttons["shape-RECTANGLE"].firstMatch.tap()
    settle()
    drag(app, (0.25, 0.60), (0.70, 0.74))
    stop(app, "ph-d6-shape-picked")
    app.buttons["pen-p1"].firstMatch.tap()
  }

  private func more(_ app: XCUIApplication) {
    app.buttons["more"].firstMatch.tap()
    settle()
  }

  func testMenusAndCards() {
    let app = openNewNotebook(["-fakePickers"])
    drag(app, (0.30, 0.44), (0.60, 0.45))
    more(app)
    stop(app, "ph-e1-more-menu")
    app.buttons["paper-more"].firstMatch.tap()
    settle()
    stop(app, "ph-e2-papers")
    // The paper in use wears a pencil: tapping it opens its card.
    app.descendants(matching: .any)["paper-GRID"].firstMatch.tap()
    settle()
    if !app.buttons["paper-card-done"].exists { app.descendants(matching: .any)["paper-GRID"].firstMatch.tap() }
    XCTAssertTrue(app.buttons["paper-card-done"].waitForExistence(timeout: 3), "the paper's card")
    stop(app, "ph-e3-paper-card")
    app.buttons["paper-card-done"].firstMatch.tap()
    settle()
    more(app)
    if !app.descendants(matching: .any)["paper-own"].exists { app.buttons["paper-more"].firstMatch.tap() }
    settle()
    app.descendants(matching: .any)["paper-own"].firstMatch.tap()
    XCTAssertTrue(app.buttons["save-paper"].waitForExistence(timeout: 3), "her own paper's card")
    settle()
    stop(app, "ph-e4-own-paper")
    scrollPanel(app)
    stop(app, "ph-e5-own-paper-scrolled")
    XCTAssertTrue(app.buttons["save-paper"].firstMatch.isHittable, "nothing lies over Save paper")
    app.buttons["Cancel"].firstMatch.tap()
    settle()
    more(app)
    app.buttons[L10n.exportPDF].firstMatch.tap()
    XCTAssertTrue(app.buttons["export-share"].waitForExistence(timeout: 8), "the export card")
    settle()
    stop(app, "ph-e6-export")
    app.buttons["Cancel"].firstMatch.tap()
    settle()
    tool(app, "tool-insert")
    stop(app, "ph-e7-insert-menu")
    app.buttons["insert-picture"].firstMatch.tap()
    XCTAssertTrue(app.buttons["selection-crop"].waitForExistence(timeout: 6), "the picture is picked up")
    stop(app, "ph-e8-picture-picked")
    app.buttons["selection-crop"].firstMatch.tap()
    XCTAssertTrue(app.buttons["crop-done"].waitForExistence(timeout: 3))
    stop(app, "ph-e9-crop")
    let done = app.buttons["crop-done"].firstMatch.frame, zoom = app.buttons["zoom-chip"].firstMatch.frame
    XCTAssertFalse(done.intersects(zoom), "the zoom chip isn't over Done")
    app.buttons["crop-done"].firstMatch.tap()
    settle()
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
    // The pages overview: the page chip's number opens it.
    app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "/ 1")).firstMatch.tap()
    settle()
    app.buttons["Add a page"].firstMatch.tap()
    app.buttons["Add a page"].firstMatch.tap()
    settle()
    stop(app, "ph-e10-pages")
    app.buttons["pages-select"].firstMatch.tap()
    settle()
    app.buttons["Pick page 1"].firstMatch.tap()
    app.buttons["Pick page 2"].firstMatch.tap()
    settle()
    stop(app, "ph-e11-pages-picking")
    app.buttons["Done"].firstMatch.tap()
    settle()
    app.buttons["Look at page 1"].firstMatch.tap()
    settle()
    stop(app, "ph-e12-page-peek")
  }

  func testMemosAndText() {
    let app = openNewNotebook()
    tool(app, "tool-voice")
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
    if allow.waitForExistence(timeout: 2) { allow.tap() }
    Thread.sleep(forTimeInterval: 2.5)
    stop(app, "ph-f1-recording")
    app.buttons["memo-done"].firstMatch.tap()
    settle()
    stop(app, "ph-f2-memo-draft")
    app.buttons["memo-add"].firstMatch.tap()
    settle()
    let memo = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Open voice memo'")).firstMatch
    XCTAssertTrue(memo.waitForExistence(timeout: 3), "the memo sits beside the page")
    memo.tap()
    settle()
    stop(app, "ph-f3-memo-open")
    at(app, 0.5, 0.9).tap()
    settle()
    tool(app, "tool-keyboard")
    guard app.keyboards.firstMatch.waitForExistence(timeout: 4) else { return XCTFail("the keyboard came") }
    if app.buttons["Continue"].exists { app.buttons["Continue"].firstMatch.tap() }
    app.typeText("Bending moment M = 4 kN m")
    settle()
    stop(app, "ph-f4-typing")
    let box = app.textViews["text-editor"].firstMatch.frame
    tool(app, "tool-lasso")
    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: box.minX + 30, dy: box.midY)).press(forDuration: 0.05)
    settle()
    XCTAssertTrue(app.buttons["selection-delete"].waitForExistence(timeout: 3), "the text is picked up")
    stop(app, "ph-f5-text-picked")
    app.buttons["pen-p1"].firstMatch.tap()
  }
}
