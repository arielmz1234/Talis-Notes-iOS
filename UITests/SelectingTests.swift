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
    // The precise one rubs out just where it passes.
    tool(app, "tool-eraser")
    app.buttons["option-true"].firstMatch.tap()
    tool(app, "tool-eraser")
    let other = CGPoint(x: f.midX + window.width * 0.34, y: f.midY)
    drag(app, CGPoint(x: other.x - 60, y: other.y), CGPoint(x: other.x + 60, y: other.y))
    calmShot("f6-precise-eraser-rubbed-part")
    app.buttons["undo"].firstMatch.tap()
    calmShot("f7-undone")
    tool(app, "tool-eraser")
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
