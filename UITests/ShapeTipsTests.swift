import XCTest

/// The Shapes tool's tips, as Android shows them: a tap that draws nothing says to drag, the part
/// circle's line in the panel, and the first shape picked up says how its dots work; each pill once.
@MainActor
final class ShapeTipsTests: ShotCase {
  private let drag = "Drag on the page to draw the shape"
  private let dots = "Drag a dot to reshape it · the menu changes its colour, thickness and line"

  private func pickShape(_ app: XCUIApplication, _ kind: String) {
    showTool(app, "tool-shapes")
    app.buttons["tool-shapes"].firstMatch.tap()
    settle()
    if !app.buttons["shape-\(kind)"].exists {
      showTool(app, "tool-shapes")
      app.buttons["tool-shapes"].firstMatch.tap()
      settle()
    }
    if app.buttons["tools-button"].exists, app.buttons["tool-lasso"].exists {
      app.buttons["tools-button"].firstMatch.tap()
      settle()
    }
    app.buttons["shape-\(kind)"].firstMatch.tap()
    settle()
  }

  private func tap(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) {
    app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
  }

  func testShapeTips() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    let app = launch()
    settle()
    app.buttons["add"].firstMatch.tap()
    settle()
    app.buttons["add-notebook"].firstMatch.tap()
    settle()
    app.buttons["create"].firstMatch.tap()
    settle()
    if app.buttons["write"].exists {
      app.buttons["write"].firstMatch.tap()
      settle()
    }
    pickShape(app, "PART_CIRCLE")
    showTool(app, "tool-shapes")
    app.buttons["tool-shapes"].firstMatch.tap()
    settle()
    XCTAssert(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Part circle: drag from the centre'")).firstMatch.exists, "the panel explains the part circle")
    shot("st1-part-circle-panel")
    pickShape(app, "RECTANGLE")
    tap(app, 0.45, 0.55)
    XCTAssert(app.staticTexts[drag].waitForExistence(timeout: 2), "a tap with the Shapes tool says to drag")
    shot("st2-drag-tip")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45))
      .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.6)), withVelocity: .slow, thenHoldForDuration: 0.05)
    XCTAssert(app.staticTexts[dots].waitForExistence(timeout: 2), "the first shape picked up says how its dots work")
    shot("st3-dots-tip")
    Thread.sleep(forTimeInterval: 3.5)
    tap(app, 0.75, 0.8)
    tap(app, 0.75, 0.8)
    XCTAssertFalse(app.staticTexts[drag].waitForExistence(timeout: 1.5), "the drag tip shows only once")
  }
}
