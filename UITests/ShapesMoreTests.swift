import XCTest

/// More shapes: the subjects' shapes, the Shapes tool's own style, the fill tool, saved shapes.
/// Settings stay on the simulator between runs, so every step chooses what it needs outright.
@MainActor
final class ShapesMoreTests: ShotCase {

  private func openNewNotebook() -> XCUIApplication {
    continueAfterFailure = true
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
    let app = launch()
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

  private func drag(_ app: XCUIApplication, _ from: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat), hold: TimeInterval = 0.05) {
    at(app, from.0, from.1).press(forDuration: 0.05, thenDragTo: at(app, to.0, to.1), withVelocity: .slow, thenHoldForDuration: hold)
    settle()
  }

  private func tool(_ app: XCUIApplication, _ id: String) {
    showTool(app, id)
    XCTAssertTrue(app.buttons[id].firstMatch.waitForExistence(timeout: 3), "\(id) is in the toolbar")
    app.buttons[id].firstMatch.tap()
    settle()
  }

  /// A shot once the page has caught up: its tiles are redrawn a moment after a tool is tapped.
  private func calmShot(_ name: String) {
    Thread.sleep(forTimeInterval: 2.5)
    shot(name)
  }

  /// The Shapes panel, whichever tool was on.
  private func shapesPanel(_ app: XCUIApplication) {
    tool(app, "tool-shapes")
    if !app.buttons["more-shapes"].exists && !app.buttons["line-SOLID"].exists { tool(app, "tool-shapes") }
  }

  /// A subject's shape in the More shapes window (the panel behind it may show the same tile).
  private func pickInWindow(_ app: XCUIApplication, _ id: String) {
    let tiles = app.buttons.matching(identifier: id)
    XCTAssertGreaterThan(tiles.count, 0, "\(id) is offered")
    tiles.element(boundBy: tiles.count - 1).tap()
    settle()
  }

  private func tab(_ app: XCUIApplication, style: Bool) {
    let tabs = app.buttons.matching(identifier: "shapes-tabs")
    XCTAssertEqual(tabs.count, 2, "Choose and Style")
    tabs.element(boundBy: style ? 1 : 0).tap()
    settle()
  }

  func testSubjectShapes() {
    let app = openNewNotebook()
    shapesPanel(app)
    tab(app, style: false)
    calmShot("s1-shapes-panel")
    XCTAssertTrue(app.buttons["shape-RECTANGLE"].exists)
    XCTAssertFalse(app.buttons["shape-SQUARE"].exists, "one rectangle tool: it snaps to a square")

    app.buttons["more-shapes"].firstMatch.tap()
    settle()
    let electrical = app.descendants(matching: .any)["subject-electrical"].firstMatch
    XCTAssertTrue(electrical.waitForExistence(timeout: 3))
    electrical.tap()
    settle()
    let star = app.buttons["star-electrical"].firstMatch
    if !star.isSelected { star.tap() }
    settle()
    calmShot("s2-more-shapes")
    XCTAssertTrue(app.buttons["pack-resistor"].exists)

    // A subject shape drawn like a line: a nearly level drag comes out level.
    pickInWindow(app, "pack-resistor")
    XCTAssertFalse(app.buttons["packs-done"].exists, "picking a shape closes the window")
    drag(app, (0.25, 0.42), (0.5, 0.43))

    // One that fills the dragged box, from another subject.
    shapesPanel(app)
    app.buttons["more-shapes"].firstMatch.tap()
    settle()
    app.descendants(matching: .any)["subject-computing"].firstMatch.tap()
    settle()
    pickInWindow(app, "pack-binary-tree")
    drag(app, (0.58, 0.34), (0.8, 0.54))
    calmShot("s3-subject-shapes-drawn")

    // The starred subject now sits in the Shapes panel.
    shapesPanel(app)
    XCTAssertTrue(app.buttons["pack-capacitor"].waitForExistence(timeout: 2), "a starred subject joins the panel")
    calmShot("s4-panel-with-starred")
  }

  func testStyle() {
    let app = openNewNotebook()
    shapesPanel(app)
    tab(app, style: true)
    calmShot("y1-style")
    XCTAssertTrue(app.buttons["line-DOT_DASH"].exists)
    app.buttons["line-LONG_DASH"].firstMatch.tap()
    XCTAssertTrue(app.buttons["no-fill"].exists)
    app.buttons["shape-fill-5"].firstMatch.tap()
    app.buttons["shape-outline-2"].firstMatch.tap()
    settle()
    calmShot("y2-style-set")

    tab(app, style: false)
    app.buttons["shape-RECTANGLE"].firstMatch.tap()
    settle()
    drag(app, (0.25, 0.36), (0.45, 0.52))
    shapesPanel(app)
    app.buttons["shape-ELLIPSE"].firstMatch.tap()
    settle()
    drag(app, (0.55, 0.36), (0.8, 0.5))
    shapesPanel(app)
    app.buttons["shape-ARROW"].firstMatch.tap()
    settle()
    drag(app, (0.3, 0.68), (0.7, 0.62))
    calmShot("y3-styled-shapes")

    // Back to a plain style for whoever runs next.
    shapesPanel(app)
    tab(app, style: true)
    app.buttons["line-SOLID"].firstMatch.tap()
    app.buttons["no-fill"].firstMatch.tap()
    app.buttons["shape-outline-0"].firstMatch.tap()
    settle()
    tab(app, style: false)
  }

  func testFill() {
    let app = openNewNotebook()
    // A box drawn by hand (its lines cross at the corners), with writing inside it.
    drag(app, (0.16, 0.42), (0.40, 0.42))
    drag(app, (0.38, 0.40), (0.38, 0.62))
    drag(app, (0.40, 0.60), (0.16, 0.60))
    drag(app, (0.18, 0.62), (0.18, 0.40))
    drag(app, (0.24, 0.53), (0.32, 0.49))
    // A triangle, and a rectangle with a line drawn across it.
    shapesPanel(app)
    tab(app, style: false)
    app.buttons["shape-TRIANGLE"].firstMatch.tap()
    settle()
    drag(app, (0.78, 0.40), (0.92, 0.60))
    shapesPanel(app)
    app.buttons["shape-RECTANGLE"].firstMatch.tap()
    settle()
    drag(app, (0.50, 0.38), (0.70, 0.62))
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
    drag(app, (0.47, 0.50), (0.73, 0.50))

    tool(app, "tool-fill")
    tool(app, "tool-fill")
    XCTAssertTrue(app.buttons["no-fill"].waitForExistence(timeout: 2), "the fill panel")
    app.buttons["fill-colour-4"].firstMatch.tap()
    calmShot("f1-fill-panel")
    tool(app, "tool-fill")

    at(app, 0.30, 0.47).tap()
    Thread.sleep(forTimeInterval: 2)
    at(app, 0.85, 0.55).tap()
    at(app, 0.60, 0.44).tap()
    calmShot("f2-filled")

    // Another colour over the drawn box replaces its fill; None takes the triangle's away.
    tool(app, "tool-fill")
    app.buttons["fill-colour-5"].firstMatch.tap()
    tool(app, "tool-fill")
    at(app, 0.30, 0.47).tap()
    Thread.sleep(forTimeInterval: 2)
    tool(app, "tool-fill")
    app.buttons["no-fill"].firstMatch.tap()
    settle()
    calmShot("f3-none")
    tool(app, "tool-fill")
    at(app, 0.85, 0.55).tap()
    calmShot("f4-recoloured-and-removed")
  }
}
