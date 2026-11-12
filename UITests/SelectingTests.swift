import XCTest

/// Selecting: the folding menu, lock, the Select panel (free form, the screenshot lasso), pictures,
/// fills and typed text in the lasso, and snapping. Settings stay on the simulator between runs, so
/// every test sets what it needs outright.
@MainActor
final class SelectingTests: ShotCase {
  private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

  private func openNewNotebook(_ extra: [String] = []) -> XCUIApplication {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
    let app = launch(extra)
    settle()
    app.buttons["add"].firstMatch.tap()
    settle()
    XCTAssertTrue(app.buttons["add-notebook"].firstMatch.waitForExistence(timeout: 4))
    app.buttons["add-notebook"].firstMatch.tap()
    XCTAssertTrue(app.buttons["create"].firstMatch.waitForExistence(timeout: 4))
    app.buttons["create"].firstMatch.tap()
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

  private func point(_ app: XCUIApplication, _ p: CGPoint) -> XCUICoordinate {
    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y))
  }

  private func drag(_ app: XCUIApplication, _ from: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat), hold: TimeInterval = 0.05) {
    at(app, from.0, from.1).press(forDuration: 0.05, thenDragTo: at(app, to.0, to.1), withVelocity: .slow, thenHoldForDuration: hold)
    settle()
  }

  private func drag(_ app: XCUIApplication, _ from: CGPoint, _ to: CGPoint, hold: TimeInterval = 0.05) {
    point(app, from).press(forDuration: 0.05, thenDragTo: point(app, to), withVelocity: .slow, thenHoldForDuration: hold)
    settle()
  }

  private func tool(_ app: XCUIApplication, _ id: String) {
    showTool(app, id)
    XCTAssertTrue(app.buttons[id].firstMatch.waitForExistence(timeout: 3), "\(id) is in the toolbar")
    app.buttons[id].firstMatch.tap()
    settle()
  }

  /// A shot once the page has caught up: its tiles are redrawn a moment after a change.
  private func calmShot(_ name: String) {
    Thread.sleep(forTimeInterval: 2)
    shot(name)
  }

  /// A shot taken while a gesture is still going (a drag held at its end), [delay] after it starts.
  private func shot(_ name: String, after delay: TimeInterval, during gesture: () -> Void) {
    final class Taken: @unchecked Sendable { var screen: XCUIScreenshot? }
    let taken = Taken()
    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { taken.screen = XCUIScreen.main.screenshot() }
    gesture()
    settle()
    // Drawn upright, as `shot` does (the picture carries its orientation).
    guard let image = taken.screen?.image, let dir = ProcessInfo.processInfo.environment["SHOT_DIR"], !dir.isEmpty else { return }
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    guard let png = UIGraphicsImageRenderer(size: image.size, format: format).image(actions: { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }).pngData() else { return }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(tag)-\(name).png"))
  }

  /// The lasso, with its panel set as asked (the panel is left closed).
  private func lasso(_ app: XCUIApplication, free: Bool = false, screenshot: Bool = false, locked: Bool = false) {
    tool(app, "tool-lasso")
    if !app.switches["lasso-screenshot"].exists { tool(app, "tool-lasso") }
    XCTAssertTrue(app.switches["lasso-screenshot"].waitForExistence(timeout: 3), "the Select panel")
    app.buttons["option-\(free)"].firstMatch.tap()
    for (id, on) in [("lasso-screenshot", screenshot), ("lasso-locked", locked)] {
      let toggle = app.switches[id].firstMatch
      if (toggle.value as? String == "1") != on { toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap() }
    }
    settle()
    tool(app, "tool-lasso")
    XCTAssertFalse(app.switches["lasso-screenshot"].exists, "the Select panel closed")
  }

  private func openMore(_ app: XCUIApplication) {
    XCTAssertTrue(app.buttons["selection-more"].firstMatch.waitForExistence(timeout: 3), "the selection menu")
    app.buttons["selection-more"].firstMatch.tap()
    settle()
  }

  /// A button of the menu's ⋯ part, scrolled into view first when the row is wider than the screen.
  private func menuButton(_ app: XCUIApplication, _ id: String) -> XCUIElement {
    let button = app.buttons[id].firstMatch
    let row = app.scrollViews["selection-row"].firstMatch
    var tries = 0
    while button.exists, !button.isHittable, row.exists, tries < 4 {
      row.swipeLeft()
      tries += 1
    }
    return button
  }

  /// Draw with finger, set from the ⋯ menu: "Auto" (fingers write in these tests), "On" or "Off".
  private func drawWithFinger(_ app: XCUIApplication, _ want: String) {
    app.buttons["more"].firstMatch.tap()
    settle()
    let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Draw with finger")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 3), "Draw with finger is in the menu")
    var tries = 0
    while !row.label.hasSuffix(want), tries < 3 {
      row.tap()
      tries += 1
    }
    at(app, 0.5, 0.92).tap()
    settle()
  }

  func testMenuFoldsAndScrolls() {
    let app = openNewNotebook()
    drag(app, (0.30, 0.44), (0.52, 0.45))
    drag(app, (0.30, 0.50), (0.52, 0.49))
    lasso(app)
    drag(app, (0.40, 0.38), (0.44, 0.56))
    XCTAssertTrue(app.buttons["selection-delete"].waitForExistence(timeout: 3), "the lasso picked the writing up")
    XCTAssertFalse(app.buttons["save-as-shape"].exists, "folded, the rest is away")
    shot("m1-folded")
    openMore(app)
    XCTAssertTrue(app.buttons["save-as-shape"].waitForExistence(timeout: 3))
    shot("m2-opened")
    let row = app.scrollViews["selection-row"].firstMatch
    if !app.buttons["save-as-shape"].firstMatch.isHittable {
      // A phone: the row is wider than the screen and scrolls sideways.
      row.swipeLeft()
      settle()
      XCTAssertTrue(app.buttons["save-as-shape"].firstMatch.isHittable, "Save as shape can be reached by scrolling")
      shot("m3-scrolled")
      row.swipeRight()
      settle()
    }
    menuButton(app, "selection-colour").tap()
    settle()
    shot("m4-colours")
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "selection-colour-")).element(boundBy: 3).tap()
    calmShot("m5-recoloured")
    menuButton(app, "selection-thickness").tap()
    settle()
    shot("m6-thickness")
    menuButton(app, "selection-mirror-v").tap()
    calmShot("m7-mirrored")
    app.buttons["selection-duplicate"].firstMatch.tap()
    settle()
    app.buttons["selection-box"].firstMatch.tap()
    calmShot("m8-duplicated-and-boxed")
    app.buttons["undo"].firstMatch.tap()
    app.buttons["undo"].firstMatch.tap()
    calmShot("m9-undone-twice")
  }

  /// A tap anywhere on a button is that button's: the right half of one isn't its neighbour's.
  func testButtonsKeepTheirWholeWidth() {
    let app = openNewNotebook()
    drag(app, (0.30, 0.44), (0.52, 0.45))
    drag(app, (0.30, 0.50), (0.52, 0.49))
    app.buttons["undo"].firstMatch.tap()
    settle()
    let undo = app.buttons["undo"].firstMatch, redo = app.buttons["redo"].firstMatch
    XCTAssertTrue(undo.isEnabled && redo.isEnabled)
    point(app, CGPoint(x: undo.frame.maxX - 8, y: undo.frame.midY)).tap()
    settle()
    XCTAssertFalse(undo.isEnabled, "the right side of Undo undoes")
    XCTAssertTrue(redo.isEnabled, "and doesn't redo")
    // The same in the selection menu: the right side of Copy copies (it doesn't cut).
    app.buttons["redo"].firstMatch.tap()
    lasso(app)
    drag(app, (0.40, 0.38), (0.44, 0.56))
    let copy = app.buttons["selection-copy"].firstMatch.frame
    point(app, CGPoint(x: copy.maxX - 8, y: copy.midY)).tap()
    settle()
    XCTAssertTrue(app.buttons["selection-delete"].exists, "still picked up: it was copied, not cut")
  }

  func testLock() {
    let app = openNewNotebook()
    drawWithFinger(app, "Auto")
    drag(app, (0.30, 0.44), (0.56, 0.45))
    tool(app, "tool-shapes")
    if !app.buttons["shape-RECTANGLE"].exists { tool(app, "tool-shapes") }
    app.buttons["shape-RECTANGLE"].firstMatch.tap()
    settle()
    drag(app, (0.60, 0.40), (0.76, 0.54))
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
    lasso(app)
    drag(app, (0.40, 0.41), (0.70, 0.49))
    openMore(app)
    menuButton(app, "selection-lock").tap()
    Thread.sleep(forTimeInterval: 0.45)
    shot("l1-locking")
    settle()
    // Locked, the lasso, a tap and the eraser all leave them alone.
    drag(app, (0.40, 0.41), (0.70, 0.49))
    XCTAssertFalse(app.buttons["selection-delete"].exists, "the lasso leaves locked things alone")
    tool(app, "tool-eraser")
    drag(app, (0.28, 0.40), (0.78, 0.52))
    calmShot("l2-lasso-and-eraser-left-them")
    app.buttons["more"].firstMatch.tap()
    settle()
    XCTAssertTrue(app.buttons["unlock-all"].waitForExistence(timeout: 3), "Unlock all is offered")
    shot("l3-unlock-all-offered")
    at(app, 0.5, 0.92).tap()
    settle()
    // A finger that doesn't write, held on a locked thing, unlocks it.
    drawWithFinger(app, "Off")
    shot("l4-holding", after: 1.2) { self.at(app, 0.41, 0.444).press(forDuration: 1.9) }
    XCTAssertTrue(app.buttons["selection-delete"].waitForExistence(timeout: 3), "held, the line unlocked and was picked up")
    shot("l5-unlocked-by-holding")
    drawWithFinger(app, "Auto")
    app.buttons["more"].firstMatch.tap()
    settle()
    XCTAssertTrue(app.buttons["unlock-all"].waitForExistence(timeout: 3), "the rectangle is still locked")
    app.buttons["unlock-all"].firstMatch.tap()
    settle()
    shot("l6-all-unlocked")
    lasso(app)
    drag(app, (0.40, 0.41), (0.70, 0.49))
    XCTAssertTrue(app.buttons["selection-delete"].waitForExistence(timeout: 3), "unlocked, they can be picked up again")
    shot("l7-picked-up-again")
  }
}
