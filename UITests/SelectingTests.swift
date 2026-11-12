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
    tapTool(app, id)
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
    foldTools(app)
  }

  /// On a phone the folded tools stay open while the tool doesn't change, over the top of the page: fold them away.
  private func foldTools(_ app: XCUIApplication) {
    if app.buttons["tools-button"].exists, app.buttons["tool-eraser"].exists {
      app.buttons["tools-button"].firstMatch.tap()
      settle()
    }
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
    // Writing takes a line style from the menu, as shapes do.
    func redInk() -> Int { Pixels().count(rows: 0.42...0.52, from: 0.28, to: 0.54) { $0.r > 170 && $0.g < 110 && $0.b < 110 } }
    let solid = redInk()
    XCTAssertTrue(app.buttons["line-DOTTED"].waitForExistence(timeout: 3), "picked-up writing is offered the line styles")
    app.buttons["line-DOTTED"].firstMatch.tap()
    Thread.sleep(forTimeInterval: 2)
    shot("m6b-dotted")
    let dotted = redInk()
    XCTAssertTrue(dotted > 0 && dotted * 10 < solid * 7, "dotted, the writing covers much less than solid: \(dotted) of \(solid) pixels")
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

  /// A tap just inside a control's right side is that control's, not its neighbour's: a rounded
  /// touch shape answered taps up to 22 pt to its left. One of each kind of neighbours.
  func testTapsStayOnTheControlUnderThem() {
    let app = openNewNotebook()
    func tapRightSide(_ e: XCUIElement) {
      XCTAssertTrue(e.waitForExistence(timeout: 3), "\(e) is there")
      point(app, CGPoint(x: e.frame.maxX - 4, y: e.frame.midY)).tap()
      settle()
    }
    func penPanel() {
      app.buttons["pen-p1"].firstMatch.tap()
      settle()
      if !app.buttons["Add a pen"].exists { app.buttons["pen-p1"].firstMatch.tap() }
      settle()
    }
    // A pen beside the arrow to the pens' settings, while they're open.
    penPanel()
    tapRightSide(app.buttons["pen-p5"].firstMatch)
    XCTAssertTrue(app.buttons["pen-p5"].firstMatch.isSelected, "the right side of the last pen picks that pen")
    // Line styles, and the two buttons at the foot of the pen's panel.
    penPanel()
    app.buttons["Dotted"].firstMatch.tap()
    settle()
    tapRightSide(app.buttons["Solid"].firstMatch)
    XCTAssertTrue(app.buttons["Solid"].firstMatch.isSelected, "the right side of Solid chooses Solid")
    if !app.buttons["colour-D83A3A"].firstMatch.isHittable { at(app, 0.5, 0.7).press(forDuration: 0.05, thenDragTo: at(app, 0.5, 0.5)) }
    tapRightSide(app.buttons["colour-D83A3A"].firstMatch)
    XCTAssertTrue(app.buttons["colour-D83A3A"].firstMatch.isSelected, "the right side of a colour picks that colour")
    let pens = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "pen-"))
    let before = pens.count
    if !app.buttons["Add a pen"].firstMatch.isHittable { at(app, 0.5, 0.7).press(forDuration: 0.05, thenDragTo: at(app, 0.5, 0.3)) }
    tapRightSide(app.buttons["Add a pen"].firstMatch)
    XCTAssertEqual(pens.count, before + 1, "the right side of Add a pen adds one (it doesn't remove this one)")
    app.buttons["Remove this pen"].firstMatch.tap()
    settle()
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
    // Shape tiles.
    tool(app, "tool-shapes")
    if !app.buttons["shape-ARROW"].exists { tool(app, "tool-shapes") }
    app.buttons["shape-ARROW"].firstMatch.tap()
    settle()
    tool(app, "tool-shapes")
    if !app.buttons["shape-LINE"].exists { tool(app, "tool-shapes") }
    tapRightSide(app.buttons["shape-LINE"].firstMatch)
    tool(app, "tool-shapes")
    if !app.buttons["shape-LINE"].exists { tool(app, "tool-shapes") }
    XCTAssertTrue(app.buttons["shape-LINE"].firstMatch.isSelected, "the right side of Line chooses the line")
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
    // The ⋯ menu: its tiles, the papers, the two chips.
    func more() {
      app.buttons["more"].firstMatch.tap()
      settle()
    }
    more()
    tapRightSide(app.buttons["Dark paper"].firstMatch)
    XCTAssertTrue(app.buttons["Dark paper"].firstMatch.isSelected, "the right side of Dark paper turns the paper dark")
    XCTAssertFalse(app.buttons["Endless canvas"].firstMatch.isSelected, "and leaves the pages as they are")
    app.buttons["Dark paper"].firstMatch.tap()
    tapRightSide(app.descendants(matching: .any)["paper-BLANK"].firstMatch)
    XCTAssertTrue(app.descendants(matching: .any)["paper-BLANK"].firstMatch.isSelected, "the right side of Blank chooses blank paper")
    tapRightSide(app.buttons["Pages"].firstMatch)
    XCTAssertTrue(app.buttons["Look at page 1"].waitForExistence(timeout: 3), "the right side of Pages opens the pages")
    app.buttons["Done"].firstMatch.tap()
    settle()
    // A card's buttons.
    more()
    app.buttons["Export PDF"].firstMatch.tap()
    XCTAssertTrue(app.buttons["export-share"].waitForExistence(timeout: 8), "the export card")
    settle()
    tapRightSide(app.buttons["Cancel"].firstMatch)
    XCTAssertFalse(app.buttons["export-share"].exists, "the right side of Cancel closes the card")
    shot("k1-every-tap-its-own")
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

  /// Where what's picked up is on screen (its dashed frame); the chips hang 14 pt off its corners.
  private func selectionFrame(_ app: XCUIApplication) -> CGRect {
    let frame = app.descendants(matching: .any)["selection-frame"].firstMatch
    XCTAssertTrue(frame.waitForExistence(timeout: 3), "something is picked up")
    return frame.frame
  }

  private func resizeChip(_ f: CGRect) -> CGPoint { CGPoint(x: f.maxX + 14, y: f.maxY + 14) }
  private func moveChip(_ f: CGRect) -> CGPoint { CGPoint(x: f.minX - 14, y: f.maxY + 14) }

  /// Writing that was copied (or moved, or loaded) stays when the eraser is used somewhere else.
  func testCopiesSurviveTheEraser() {
    let app = openNewNotebook()
    drag(app, (0.16, 0.42), (0.40, 0.42))
    lasso(app)
    drag(app, (0.27, 0.38), (0.29, 0.46))
    let one = selectionFrame(app).height
    app.buttons["selection-duplicate"].firstMatch.tap()
    settle()
    tool(app, "tool-eraser")
    foldTools(app)
    drag(app, (0.60, 0.70), (0.62, 0.71))
    lasso(app)
    drag(app, (0.27, 0.38), (0.29, 0.50))
    XCTAssertGreaterThan(selectionFrame(app).height, one + 3, "the line and its copy are both still there")
    calmShot("e1-copy-survived-the-eraser")
  }

  /// The lasso never picks up a whole PDF page, however much of it the loop holds.
  func testAPdfPageIsNeverPickedUp() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
    let app = launch()
    settle()
    let pdf = app.descendants(matching: .any)["notebook-Lecture slides"].firstMatch
    XCTAssertTrue(pdf.waitForExistence(timeout: 5), "the seeded PDF is in the library")
    pdf.tap()
    settle()
    if app.buttons["write"].exists {
      app.buttons["write"].firstMatch.tap()
      settle()
    }
    drag(app, (0.40, 0.50), (0.60, 0.52))
    lasso(app)
    drag(app, (0.30, 0.40), (0.70, 0.62))
    XCTAssertLessThan(selectionFrame(app).height, app.windows.firstMatch.frame.height * 0.1, "only the writing, not the page under it")
    shot("d1-pdf-page-left-alone")
    at(app, 0.5, 0.85).tap()
    settle()
    at(app, 0.5, 0.7).tap()
    XCTAssertFalse(app.buttons["selection-delete"].waitForExistence(timeout: 1.5), "a lasso tap on the page picks nothing up")
  }

  func testSelectPanel() {
    let app = openNewNotebook()
    drag(app, (0.30, 0.40), (0.50, 0.41))
    drag(app, (0.30, 0.52), (0.50, 0.51))
    drag(app, (0.62, 0.46), (0.78, 0.47))
    tool(app, "tool-lasso")
    if !app.switches["lasso-screenshot"].exists { tool(app, "tool-lasso") }
    shot("p1-select-panel")
    // Free form: tracing over the top line picks it up, and only it.
    lasso(app, free: true)
    drag(app, (0.40, 0.36), (0.40, 0.45))
    let one = selectionFrame(app)
    XCTAssertLessThan(one.height, app.windows.firstMatch.frame.height * 0.08, "only the line traced over")
    shot("p2-free-form")
    // The screenshot lasso: the rectangle round what's drawn becomes a picture.
    lasso(app, free: false, screenshot: true)
    at(app, 0.5, 0.66).tap()
    settle()
    drag(app, (0.28, 0.36), (0.80, 0.56))
    XCTAssertTrue(app.buttons["screenshot-copy"].waitForExistence(timeout: 6), "the screenshot is offered")
    calmShot("p3-screenshot")
    app.buttons["screenshot-copy"].firstMatch.tap()
    Thread.sleep(forTimeInterval: 0.8)
    shot("p4-copied")
    settle()
    // Copied, it pastes where she holds, like anything copied.
    at(app, 0.5, 0.72).press(forDuration: 1.0)
    XCTAssertTrue(app.buttons["paste"].waitForExistence(timeout: 3), "holding offers Paste")
    shot("p5-paste-offered")
    app.buttons["paste"].firstMatch.tap()
    XCTAssertTrue(app.buttons["selection-crop"].waitForExistence(timeout: 4), "the pasted screenshot is a picture, picked up")
    calmShot("p6-pasted")
    lasso(app)
  }

  func testPicturesInTheLasso() {
    let app = openNewNotebook(["-fakePickers"])
    let window = app.windows.firstMatch.frame
    tool(app, "tool-insert")
    app.buttons["insert-picture"].firstMatch.tap()
    XCTAssertTrue(app.buttons["selection-crop"].waitForExistence(timeout: 6), "a new picture is picked up, Crop first")
    calmShot("i1-picture-picked")
    var f = selectionFrame(app)
    // Carried by its move chip, then made smaller from its corner.
    drag(app, moveChip(f), CGPoint(x: moveChip(f).x - window.width * 0.06, y: moveChip(f).y + window.height * 0.04))
    f = selectionFrame(app)
    let grip = resizeChip(f)
    drag(app, grip, CGPoint(x: f.minX + (grip.x - f.minX) * 0.7, y: f.minY + (grip.y - f.minY) * 0.7))
    let smaller = selectionFrame(app)
    XCTAssertLessThan(smaller.width, f.width * 0.85, "resized from the corner")
    calmShot("i2-moved-and-resized")
    openMore(app)
    XCTAssertFalse(app.buttons["selection-colour"].exists, "a picture has no colour or thickness to change")
    XCTAssertFalse(app.buttons["selection-thickness"].exists)
    XCTAssertFalse(app.buttons["save-as-shape"].exists)
    menuButton(app, "selection-front").tap()
    Thread.sleep(forTimeInterval: 0.6)
    shot("i3-brought-to-the-front")
    settle()
    // A loop drawn wholly inside a picture leaves it; one across its edge picks it up.
    lasso(app)
    at(app, 0.5, 0.88).tap()
    settle()
    let inside = CGPoint(x: smaller.midX, y: smaller.midY)
    drag(app, CGPoint(x: inside.x - 20, y: inside.y + 24), CGPoint(x: inside.x + 20, y: inside.y + 40))
    XCTAssertFalse(app.buttons["selection-delete"].exists, "a loop inside the picture leaves it")
    drag(app, CGPoint(x: smaller.minX - 30, y: smaller.midY - 20), CGPoint(x: smaller.minX + 40, y: smaller.midY + 20))
    XCTAssertTrue(app.buttons["selection-crop"].waitForExistence(timeout: 3), "a loop across its edge picks it up")
    // Crop, from its menu.
    app.buttons["selection-crop"].firstMatch.tap()
    XCTAssertTrue(app.buttons["crop-done"].waitForExistence(timeout: 3))
    let c = app.descendants(matching: .any)["crop-frame"].firstMatch.frame
    drag(app, CGPoint(x: c.minX, y: c.midY), CGPoint(x: c.minX + c.width * 0.3, y: c.midY), hold: 0.1)
    shot("i4-cropping")
    app.buttons["crop-done"].firstMatch.tap()
    XCTAssertTrue(app.buttons["selection-crop"].waitForExistence(timeout: 3), "cropped, it's picked up again")
    calmShot("i5-cropped")
  }

  func testFillsFollowTheirOutline() {
    let app = openNewNotebook()
    let window = app.windows.firstMatch.frame
    // A box drawn by hand (its lines cross at the corners), filled.
    drag(app, (0.16, 0.42), (0.40, 0.42))
    drag(app, (0.38, 0.40), (0.38, 0.62))
    drag(app, (0.40, 0.60), (0.16, 0.60))
    drag(app, (0.18, 0.62), (0.18, 0.40))
    tool(app, "tool-fill")
    if !app.buttons["no-fill"].exists { tool(app, "tool-fill") }
    app.buttons["fill-colour-4"].firstMatch.tap()
    tool(app, "tool-fill")
    at(app, 0.28, 0.51).tap()
    Thread.sleep(forTimeInterval: 2.5)
    // The lasso across one side picks up the whole box and its fill.
    lasso(app)
    drag(app, (0.27, 0.38), (0.29, 0.46))
    var f = selectionFrame(app)
    XCTAssertGreaterThan(f.height, window.height * 0.15, "one side brings the fill and the rest of its outline")
    calmShot("f1-fill-picked-with-its-outline")
    drag(app, CGPoint(x: f.midX, y: f.midY), CGPoint(x: f.midX + window.width * 0.34, y: f.midY + window.height * 0.02))
    calmShot("f2-moved-together")
    app.buttons["selection-duplicate"].firstMatch.tap()
    settle()
    f = selectionFrame(app)
    drag(app, CGPoint(x: f.midX, y: f.midY), CGPoint(x: f.midX - window.width * 0.34, y: f.midY + window.height * 0.01))
    calmShot("f3-duplicate-keeps-its-fill")
    openMore(app)
    menuButton(app, "selection-mirror-h").tap()
    calmShot("f4-mirrored")
    // The eraser treats them apart: whole strokes takes the whole fill and leaves its outline.
    f = selectionFrame(app)
    tool(app, "tool-eraser")
    if !app.buttons["option-false"].exists { tool(app, "tool-eraser") }
    app.buttons["option-false"].firstMatch.tap()
    tool(app, "tool-eraser")
    drag(app, CGPoint(x: f.midX - 10, y: f.midY), CGPoint(x: f.midX + 10, y: f.midY + 4))
    calmShot("f5-stroke-eraser-took-the-fill")
    let other = CGPoint(x: f.midX + window.width * 0.34, y: f.midY)
    func filled(_ p: CGPoint) -> Bool {
      let c = Pixels().colour(x: p.x / window.width, y: p.y / window.height)
      return c.g > c.r + 40 && c.g > c.b + 20
    }
    // Clear of where the eraser passes.
    let above: CGFloat = -30
    XCTAssertFalse(filled(CGPoint(x: f.midX, y: f.midY + above)), "the stroke eraser takes the whole fill, not only where it passed")
    XCTAssertTrue(filled(other), "the other fill is untouched")
    // The precise one rubs out just where it passes.
    tool(app, "tool-eraser")
    app.buttons["option-true"].firstMatch.tap()
    tool(app, "tool-eraser")
    drag(app, CGPoint(x: other.x - 60, y: other.y), CGPoint(x: other.x + 60, y: other.y))
    calmShot("f6-precise-eraser-rubbed-part")
    XCTAssertFalse(filled(other), "the precise eraser rubs the fill out where it passes")
    XCTAssertTrue(filled(CGPoint(x: other.x, y: other.y + above)), "and leaves the rest of it")
    app.buttons["undo"].firstMatch.tap()
    calmShot("f7-undone")
    XCTAssertTrue(filled(other), "one undo puts back what that pass rubbed out")
    XCTAssertFalse(filled(CGPoint(x: f.midX, y: f.midY + above)), "and no more than that pass")
    tool(app, "tool-eraser")
    app.buttons["option-false"].firstMatch.tap()
    tool(app, "tool-eraser")
  }

  /// A fill's outline cut by the precise eraser still belongs to the fill: the pieces travel with
  /// the fill and the rest of its outline.
  func testACutOutlineStaysWithItsFill() {
    let app = openNewNotebook()
    let window = app.windows.firstMatch.frame
    drag(app, (0.16, 0.42), (0.40, 0.42))
    drag(app, (0.38, 0.40), (0.38, 0.62))
    drag(app, (0.40, 0.60), (0.16, 0.60))
    drag(app, (0.18, 0.62), (0.18, 0.40))
    tool(app, "tool-fill")
    if !app.buttons["no-fill"].exists { tool(app, "tool-fill") }
    app.buttons["fill-colour-4"].firstMatch.tap()
    tool(app, "tool-fill")
    at(app, 0.28, 0.51).tap()
    Thread.sleep(forTimeInterval: 2.5)
    // The top side cut in two, a quarter of the way along.
    tool(app, "tool-eraser")
    if !app.buttons["option-true"].exists { tool(app, "tool-eraser") }
    app.buttons["option-true"].firstMatch.tap()
    tool(app, "tool-eraser")
    foldTools(app)
    drag(app, (0.24, 0.395), (0.24, 0.43))
    calmShot("c1-outline-cut")
    // Picked up by its right side and carried away: both pieces of the cut side go too.
    func topSide(shiftedBy dx: CGFloat) -> Int {
      Pixels().count(rows: 0.405...0.435, from: 0.20 + dx, to: 0.36 + dx) { $0.r < 110 && $0.g < 110 && $0.b < 125 }
    }
    XCTAssertGreaterThan(topSide(shiftedBy: 0), 20, "the cut side is still drawn")
    lasso(app)
    drag(app, (0.37, 0.50), (0.39, 0.52))
    let f = selectionFrame(app)
    drag(app, CGPoint(x: f.midX, y: f.midY), CGPoint(x: f.midX + window.width * 0.4, y: f.midY))
    at(app, 0.5, 0.85).tap()
    calmShot("c2-carried-with-its-cut-side")
    XCTAssertEqual(topSide(shiftedBy: 0), 0, "nothing of the cut side stays behind")
    XCTAssertGreaterThan(topSide(shiftedBy: 0.4), 20, "its pieces went with the fill")
    tool(app, "tool-eraser")
    if !app.buttons["option-false"].exists { tool(app, "tool-eraser") }
    app.buttons["option-false"].firstMatch.tap()
    tool(app, "tool-eraser")
  }

  func testTypedTextInTheLasso() {
    let app = openNewNotebook()
    tool(app, "tool-keyboard")
    guard app.keyboards.firstMatch.waitForExistence(timeout: 4) else { return XCTFail("the keyboard came") }
    if app.buttons["Continue"].exists { app.buttons["Continue"].firstMatch.tap() }
    app.typeText("Reaction R = 12 kN")
    let box = app.textViews["text-editor"].firstMatch.frame
    lasso(app)
    point(app, CGPoint(x: box.minX + 40, y: box.midY)).press(forDuration: 0.05)
    var f = selectionFrame(app)
    shot("t1-text-picked")
    // Resized from the corner the text grows; moved by its chip.
    let grip = resizeChip(f)
    drag(app, grip, CGPoint(x: f.minX + (grip.x - f.minX) * 1.15, y: f.minY + (grip.y - f.minY) * 1.15))
    let bigger = selectionFrame(app)
    XCTAssertGreaterThan(bigger.width, f.width * 1.08, "the text grew")
    f = bigger
    drag(app, moveChip(f), CGPoint(x: moveChip(f).x + 30, y: moveChip(f).y + 60))
    calmShot("t2-bigger-and-moved")
    openMore(app)
    XCTAssertFalse(app.buttons["selection-thickness"].exists, "text has no thickness")
    XCTAssertFalse(app.buttons["selection-mirror-h"].isHittable && app.buttons["save-as-shape"].exists, "text alone can't be saved as a shape")
    menuButton(app, "selection-colour").tap()
    settle()
    app.buttons["selection-colour-3"].firstMatch.tap()
    calmShot("t3-recoloured")
    menuButton(app, "selection-edit-text").tap()
    let editor = app.textViews["text-editor"].firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 3), "Edit text opens the box")
    XCTAssertFalse(app.keyboards.firstMatch.exists, "picked up first: no keyboard until it's tapped")
    calmShot("t4-edit-text")
    // The box is sized like a rectangle: the right side's dot sets its width, the bottom one its height.
    let wide = editor.frame
    let right = app.descendants(matching: .any)["text-side-1"].firstMatch.frame
    drag(app, CGPoint(x: right.midX, y: right.midY), CGPoint(x: right.midX - wide.width * 0.45, y: right.midY))
    let bottom = app.descendants(matching: .any)["text-side-3"].firstMatch.frame
    drag(app, CGPoint(x: bottom.midX, y: bottom.midY), CGPoint(x: bottom.midX, y: bottom.midY + 60))
    XCTAssertLessThan(editor.frame.width, wide.width * 0.7, "narrower from its right side")
    XCTAssertEqual(editor.frame.minX, wide.minX, accuracy: 1, "the left side stayed put")
    XCTAssertGreaterThan(editor.frame.height, wide.height + 40, "taller from its bottom side")
    calmShot("t5-box-resized-by-its-sides")
    let move = app.descendants(matching: .any)["text-move"].firstMatch.frame
    drag(app, CGPoint(x: move.midX, y: move.midY), CGPoint(x: move.midX + 80, y: move.midY + 40))
    XCTAssertEqual(editor.frame.minX, wide.minX + 80, accuracy: 6, "carried by its move chip")
    // Between its dots (on a phone the box is small and they stand close together).
    point(app, CGPoint(x: editor.frame.minX + editor.frame.width * 0.25, y: editor.frame.minY + 5)).tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4), "a tap on it brings the keyboard")
    calmShot("t6-typing")
    // A tap elsewhere finishes it; the box keeps its new place and size.
    at(app, 0.5, 0.2).tap()
    XCTAssertFalse(app.textViews["text-editor"].waitForExistence(timeout: 1.5), "a tap elsewhere finishes the text")
    calmShot("t7-kept")
  }

  /// The small bar above a text box being typed in: size, colour, delete and done.
  func testTextBar() {
    let app = openNewNotebook()
    let window = app.windows.firstMatch.frame
    tool(app, "tool-keyboard")
    guard app.keyboards.firstMatch.waitForExistence(timeout: 4) else { return XCTFail("the keyboard came") }
    if app.buttons["Continue"].exists { app.buttons["Continue"].firstMatch.tap() }
    app.typeText("Shear V = 6 kN")
    let editor = app.textViews["text-editor"].firstMatch
    for id in ["text-smaller", "text-bigger", "text-colour-0", "text-delete", "text-done"] {
      let b = app.buttons[id].firstMatch
      XCTAssertTrue(b.waitForExistence(timeout: 3) && b.isHittable, "\(id) is in the bar")
      XCTAssertTrue(window.contains(b.frame), "\(id) is on the screen, at \(b.frame)")
      XCTAssertLessThan(b.frame.maxY, editor.frame.minY, "the bar sits above the box")
    }
    XCTAssertGreaterThan(app.buttons["text-smaller"].firstMatch.frame.minY, app.buttons["pen-p1"].firstMatch.frame.maxY, "and below the toolbars")
    shot("b1-text-bar")
    let small = editor.frame.height
    for _ in 0..<4 { app.buttons["text-bigger"].firstMatch.tap() }
    settle()
    XCTAssertGreaterThan(editor.frame.height, small * 1.5, "A+ makes the text bigger")
    app.buttons["text-smaller"].firstMatch.tap()
    settle()
    XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard stays while the bar is used")
    // Her fourth colour is red.
    app.buttons["text-colour-3"].firstMatch.tap()
    settle()
    let box = editor.frame
    shot("b2-bigger-and-red")
    app.buttons["text-done"].firstMatch.tap()
    XCTAssertFalse(app.textViews["text-editor"].waitForExistence(timeout: 1.5), "Done finishes the text")
    XCTAssertFalse(app.buttons["text-done"].exists, "and the bar goes with it")
    func redText() -> Int {
      Pixels().count(rows: (box.minY / window.height)...(box.maxY / window.height), from: box.minX / window.width, to: min(box.maxX / window.width, 0.99)) { $0.r > 170 && $0.g < 110 && $0.b < 110 }
    }
    Thread.sleep(forTimeInterval: 2)
    shot("b3-done")
    XCTAssertGreaterThan(redText(), 8, "the text is on the page in the colour chosen")
    // Opened again from its menu, the bar's bin deletes it; undo brings it back.
    lasso(app)
    point(app, CGPoint(x: box.minX + 16, y: box.midY)).press(forDuration: 0.05)
    openMore(app)
    menuButton(app, "selection-edit-text").tap()
    XCTAssertTrue(app.buttons["text-delete"].waitForExistence(timeout: 3), "the bar comes with the box picked up")
    shot("b4-opened-again")
    app.buttons["text-delete"].firstMatch.tap()
    XCTAssertFalse(app.textViews["text-editor"].waitForExistence(timeout: 1.5))
    Thread.sleep(forTimeInterval: 2)
    shot("b5-deleted")
    XCTAssertEqual(redText(), 0, "the bin deletes the text")
    app.buttons["undo"].firstMatch.tap()
    Thread.sleep(forTimeInterval: 2)
    XCTAssertGreaterThan(redText(), 8, "undo brings it back")
  }

  /// What's picked up, carried to the bottom of the screen and rested there, scrolls the page along
  /// and stays under the finger.
  func testCarryingToAnEdgeScrollsThePage() {
    let app = openNewNotebook()
    let window = app.windows.firstMatch.frame
    func onPage(_ n: Int) -> Bool { app.buttons.matching(NSPredicate(format: "label == %@", "\(n) / 3")).firstMatch.exists }
    // Three pages, so there's somewhere to scroll to on any screen.
    app.buttons.matching(NSPredicate(format: "label == %@", "1 / 1")).firstMatch.tap()
    settle()
    app.buttons["Add a page"].firstMatch.tap()
    app.buttons["Add a page"].firstMatch.tap()
    app.buttons["Done"].firstMatch.tap()
    settle()
    drag(app, (0.30, 0.44), (0.52, 0.45))
    lasso(app)
    drag(app, (0.40, 0.38), (0.44, 0.56))
    let f = selectionFrame(app)
    XCTAssertTrue(onPage(1), "it starts on page 1 of 3")
    // Across the bottom edge's zone and straight back: passing through doesn't scroll.
    let grab = CGPoint(x: f.midX, y: f.midY)
    point(app, grab).press(forDuration: 0.05, thenDragTo: point(app, CGPoint(x: grab.x, y: window.height * 0.6)), withVelocity: .fast, thenHoldForDuration: 0.05)
    settle()
    XCTAssertTrue(onPage(1), "carried about in the middle of the screen, the page stays")
    let now = selectionFrame(app)
    shot("g1-resting-at-the-edge", after: 2.5) {
      self.point(app, CGPoint(x: now.midX, y: now.midY)).press(
        forDuration: 0.05, thenDragTo: self.point(app, CGPoint(x: now.midX, y: window.height - 20)), withVelocity: .slow, thenHoldForDuration: 4)
    }
    XCTAssertFalse(onPage(1), "rested at the bottom edge, the page scrolled along")
    XCTAssertGreaterThan(selectionFrame(app).midY, window.height * 0.7, "and what's carried stayed under the finger")
    calmShot("g2-carried-to-a-later-page")
  }

  func testSnapping() {
    let app = openNewNotebook()
    let window = app.windows.firstMatch.frame
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: window.width * x, y: window.height * y) }
    tool(app, "tool-shapes")
    if !app.buttons["shape-RECTANGLE"].exists { tool(app, "tool-shapes") }
    app.buttons["shape-RECTANGLE"].firstMatch.tap()
    settle()
    let a0 = pt(0.20, 0.36), a1 = pt(0.38, 0.50)
    drag(app, a0, a1)
    drag(app, pt(0.56, 0.42), pt(0.70, 0.52))
    // Carried so its left side comes a few points off the first one's right side, its top a few off its top.
    let b = selectionFrame(app)
    let grab = CGPoint(x: b.midX, y: b.midY)
    let to = CGPoint(x: grab.x - (b.minX + 9 - a1.x) + 6, y: grab.y - (b.minY + 9 - a0.y) + 5)
    shot("n1-guides-while-moving", after: 3.0) {
      self.point(app, grab).press(forDuration: 0.05, thenDragTo: self.point(app, to), withVelocity: .slow, thenHoldForDuration: 3.2)
    }
    let snapped = selectionFrame(app)
    XCTAssertEqual(snapped.minX + 9.2, a1.x, accuracy: 2.5, "its side locked onto the other's side")
    XCTAssertEqual(snapped.minY + 9.2, a0.y, accuracy: 2.5, "its top lined up with the other's top")
    calmShot("n2-snapped")
    // A line drawn from near the corner starts on the corner and ends on the other box's side.
    tool(app, "tool-shapes")
    if !app.buttons["shape-LINE"].exists { tool(app, "tool-shapes") }
    app.buttons["shape-LINE"].firstMatch.tap()
    settle()
    shot("n3-line-end-locking", after: 2.6) {
      self.point(app, CGPoint(x: a0.x + 5, y: a1.y + 4)).press(
        forDuration: 0.05, thenDragTo: self.point(app, CGPoint(x: a0.x + 4, y: a1.y + window.height * 0.2)), withVelocity: .slow, thenHoldForDuration: 2.6)
    }
    calmShot("n4-line-from-the-corner")
    // A subject shape shows its joints as dots.
    tool(app, "tool-shapes")
    if !app.buttons["more-shapes"].exists { tool(app, "tool-shapes") }
    app.buttons["more-shapes"].firstMatch.tap()
    settle()
    app.descendants(matching: .any)["subject-computing"].firstMatch.tap()
    settle()
    let tiles = app.buttons.matching(identifier: "pack-binary-tree")
    tiles.element(boundBy: tiles.count - 1).tap()
    settle()
    drag(app, pt(0.56, 0.60), pt(0.78, 0.84))
    calmShot("n5-joint-dots")
  }
}
