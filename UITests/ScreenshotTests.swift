import XCTest

/// The tour CI has always taken: library, a new notebook, writing, the tools, reopening, a PDF.
@MainActor
final class ScreenshotTests: ShotCase {

  private func at(_ app: XCUIApplication, _ p: CGPoint) -> XCUICoordinate {
    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y))
  }

  private func drag(_ app: XCUIApplication, _ a: CGPoint, _ b: CGPoint) {
    at(app, a).press(forDuration: 0.1, thenDragTo: at(app, b), withVelocity: .slow, thenHoldForDuration: 0.05)
    settle()
  }

  private func pickShape(_ app: XCUIApplication, _ kind: String) {
    showTool(app, "tool-shapes")
    app.buttons["tool-shapes"].firstMatch.tap()
    settle()
    if !app.buttons["shape-\(kind)"].exists {
      showTool(app, "tool-shapes")
      app.buttons["tool-shapes"].firstMatch.tap()
      settle()
    }
    // The phone's folded tools stay open while the tool doesn't change, over the panel's tiles: fold them away.
    if app.buttons["tools-button"].exists, app.buttons["tool-lasso"].exists {
      app.buttons["tools-button"].firstMatch.tap()
      settle()
    }
    app.buttons["shape-\(kind)"].firstMatch.tap()
    settle()
  }

  func testShapeDotsAndSelectionHandles() {
    continueAfterFailure = true
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
    let app = launch()
    settle()
    app.buttons["add"].firstMatch.tap()
    settle()
    let notebookItem = app.buttons["add-notebook"].firstMatch
    if notebookItem.waitForExistence(timeout: 3) {
      notebookItem.tap()
      settle()
    }
    app.buttons["create"].firstMatch.tap()
    settle()
    if app.buttons["write"].exists {
      app.buttons["write"].firstMatch.tap()
      settle()
    }
    let size = app.windows.firstMatch.frame.size
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: size.width * x, y: size.height * y) }
    // The selection's frame stands 8 off what's picked up; the chips sit 14 further out, the rotate handle 30 below.
    let gap: CGFloat = 8, chip: CGFloat = 14, drop: CGFloat = 30

    // Two lines of writing, for the lasso later.
    drag(app, pt(0.70, 0.46), pt(0.84, 0.47))
    drag(app, pt(0.70, 0.50), pt(0.84, 0.495))

    pickShape(app, "RECTANGLE")
    let a = pt(0.24, 0.34), b = pt(0.42, 0.46)
    drag(app, a, b)
    shot("s1-rectangle-drawn")
    let wider = b.x + size.width * 0.1
    drag(app, CGPoint(x: b.x, y: (a.y + b.y) / 2), CGPoint(x: wider, y: (a.y + b.y) / 2 + 12))
    shot("s2-dot-dragged")
    app.buttons["undo"].firstMatch.tap()
    settle()
    shot("s3-undone")
    app.buttons["redo"].firstMatch.tap()
    settle()
    at(app, CGPoint(x: (a.x + wider) / 2, y: a.y)).press(forDuration: 0.05)
    settle()
    shot("s4-tapped")
    let grip = CGPoint(x: wider + gap + chip, y: b.y + gap + chip)
    drag(app, grip, CGPoint(x: a.x + (grip.x - a.x) * 1.25, y: a.y + (grip.y - a.y) * 1.25))
    shot("s5-resized")
    // 40° round is near enough to snap to 45°.
    let corner = CGPoint(x: a.x + (wider - a.x) * 1.25, y: a.y + (b.y - a.y) * 1.25)
    let middle = CGPoint(x: (a.x + corner.x) / 2, y: (a.y + corner.y) / 2)
    let reach = corner.y + gap + drop - middle.y
    let turn = 40 * CGFloat.pi / 180
    drag(app, CGPoint(x: middle.x, y: middle.y + reach), CGPoint(x: middle.x - reach * sin(turn), y: middle.y + reach * cos(turn)))
    shot("s6-turned")

    pickShape(app, "LINE")
    let l0 = pt(0.22, 0.76), l1 = pt(0.50, 0.765)
    drag(app, l0, l1)
    shot("s7-line")
    drag(app, CGPoint(x: l1.x, y: l0.y), pt(0.44, 0.68))
    shot("s8-line-end-dragged")

    pickShape(app, "PART_CIRCLE")
    let centre = pt(0.68, 0.74), radius = size.width * 0.1
    drag(app, centre, CGPoint(x: centre.x + radius, y: centre.y))
    shot("s9-part-circle")
    drag(app, CGPoint(x: centre.x, y: centre.y + radius), CGPoint(x: centre.x - radius, y: centre.y + 4))
    shot("s10-part-circle-end-dragged")

    // The top corner goes almost straight above the left one: near enough to lock on to a right angle.
    pickShape(app, "TRIANGLE")
    let t0 = pt(0.70, 0.30), t1 = pt(0.84, 0.42)
    drag(app, t0, t1)
    drag(app, CGPoint(x: (t0.x + t1.x) / 2, y: t0.y), CGPoint(x: t0.x + 3, y: t0.y + 2))
    shot("s11-triangle-corner-dragged")

    // Through the pen: with the Shapes tool on, a tap on the lasso opens the Shapes panel instead.
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
    showTool(app, "tool-lasso")
    app.buttons["tool-lasso"].firstMatch.tap()
    settle()
    drag(app, pt(0.66, 0.28), pt(0.80, 0.56))
    shot("s12-lasso")
    let carry = CGVector(dx: -size.width * 0.03, dy: size.height * 0.03)
    let handle = CGPoint(x: t0.x - gap - chip, y: pt(0, 0.50).y + gap + chip)
    drag(app, handle, CGPoint(x: handle.x + carry.dx, y: handle.y + carry.dy))
    shot("s13-lasso-moved")
    let top = CGPoint(x: t0.x + carry.dx, y: t0.y + carry.dy), low = CGPoint(x: pt(0.84, 0).x + carry.dx, y: pt(0, 0.50).y + carry.dy)
    let lassoGrip = CGPoint(x: low.x + gap + chip, y: low.y + gap + chip)
    drag(app, lassoGrip, CGPoint(x: top.x + (lassoGrip.x - top.x) * 0.8, y: top.y + (lassoGrip.y - top.y) * 0.8))
    shot("s14-lasso-resized")
    let smaller = CGPoint(x: top.x + (low.x - top.x) * 0.8, y: top.y + (low.y - top.y) * 0.8)
    let pivot = CGPoint(x: (top.x + smaller.x) / 2, y: (top.y + smaller.y) / 2)
    let arm = smaller.y + gap + drop - pivot.y
    let quarter = 86 * CGFloat.pi / 180
    drag(app, CGPoint(x: pivot.x, y: pivot.y + arm), CGPoint(x: pivot.x - arm * sin(quarter), y: pivot.y + arm * cos(quarter)))
    shot("s15-lasso-turned")
    app.buttons["undo"].firstMatch.tap()
    settle()
    shot("s16-turn-undone")

    showTool(app, "pen-p1")
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
    at(app, CGPoint(x: centre.x, y: centre.y - radius / 2)).press(forDuration: 0.05)
    settle()
    shot("s17-pen-tap")

    showTool(app, "tool-keyboard")
    app.buttons["tool-keyboard"].firstMatch.tap()
    settle()
    guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else { return }
    // A fresh simulator first explains slide-to-type.
    if app.buttons["Continue"].exists { app.buttons["Continue"].firstMatch.tap() }
    app.typeText("Reaction R = 12 kN")
    let box = app.textViews["text-editor"].firstMatch.frame
    showTool(app, "tool-lasso")
    app.buttons["tool-lasso"].firstMatch.tap()
    settle()
    guard !box.isEmpty else { return }
    at(app, CGPoint(x: box.midX, y: box.midY)).press(forDuration: 0.05)
    settle()
    shot("s18-text-picked")
    let textGrip = CGPoint(x: box.maxX + gap + chip, y: box.maxY + gap + chip)
    drag(app, textGrip, CGPoint(x: box.minX + (textGrip.x - box.minX) * 0.7, y: box.minY + (textGrip.y - box.minY) * 0.7))
    shot("s19-text-resized")
  }

  func testLibraryAndNotebook() {
    continueAfterFailure = true
    let device = XCUIDevice.shared
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    device.orientation = isPad ? .landscapeLeft : .portrait
    let app = launch()
    settle()
    shot("1-library")
    if isPad {
      device.orientation = .portrait
      settle()
      shot("2-library-portrait")
      device.orientation = .landscapeLeft
      settle()
    }
    app.buttons["add"].firstMatch.tap()
    settle()
    // The + is a menu: Notebook opens the new-notebook card.
    let notebookItem = app.buttons["add-notebook"].firstMatch
    if notebookItem.waitForExistence(timeout: 3) {
      shot("2b-add-menu")
      notebookItem.tap()
      settle()
      if !app.buttons["create"].waitForExistence(timeout: 4) { shot("3x-after-notebook-tap") }
    }
    shot("3-new-notebook")
    app.buttons["create"].firstMatch.tap()
    settle()
    // On a phone it opens just for looking: one shot of that, then Write.
    if app.buttons["write"].exists {
      shot("4a-viewing")
      app.buttons["write"].firstMatch.tap()
      settle()
    }
    // A quick zigzag with a finger (UI tests let a finger draw).
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
    start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)))
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55))
      .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.62)))
    // Hold-to-shape: a slightly sloping line, held at its end, snaps level.
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.78))
      .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.8)), withVelocity: .slow, thenHoldForDuration: 1.2)
    settle()
    shot("4-notebook")
    // The pen's panel with its thickness slider (glass on iOS 26).
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
    shot("4b-pen-panel")
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
    // The lasso: a loop round the strokes picks them up and shows the selection menu.
    showTool(app, "tool-lasso")
    if app.buttons["tool-lasso"].exists {
      app.buttons["tool-lasso"].firstMatch.tap()
      settle()
      // A slow drag so the loop gets plenty of points (a fast one is just its two ends).
      let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.38))
      a.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.72)), withVelocity: .slow, thenHoldForDuration: 0.05)
      settle()
      shot("4d-lasso")
      app.buttons["pen-p1"].firstMatch.tap()
      settle()
    }
    // The Shapes tool: its panel opens, an ellipse is chosen and dragged out.
    showTool(app, "tool-shapes")
    if app.buttons["tool-shapes"].exists {
      app.buttons["tool-shapes"].firstMatch.tap()
      settle()
      shot("4e-shapes-panel")
      if app.buttons["shape-ELLIPSE"].exists {
        app.buttons["shape-ELLIPSE"].firstMatch.tap()
        settle()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.3))
          .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.42)), withVelocity: .slow, thenHoldForDuration: 0.05)
        settle()
        shot("4f-shape-drawn")
      }
      app.buttons["pen-p1"].firstMatch.tap()
      settle()
    }
    // Typed text: the keyboard opens a box below what's written; the lasso tool puts it down.
    showTool(app, "tool-keyboard")
    if app.buttons["tool-keyboard"].exists {
      app.buttons["tool-keyboard"].firstMatch.tap()
      settle()
      // The box sits inside PencilKit's canvas, which hides its subviews from accessibility:
      // type into whatever has the keyboard, as a person would.
      if app.keyboards.firstMatch.waitForExistence(timeout: 3) {
        app.typeText("Sum of moments = 0\nReaction R = 12 kN")
      } else {
        XCTFail("no keyboard for the new text box")
      }
      shot("4g-typing")
      showTool(app, "tool-lasso")
      if app.buttons["tool-lasso"].exists { app.buttons["tool-lasso"].firstMatch.tap() }
      settle()
      shot("4h-text")
      app.buttons["pen-p1"].firstMatch.tap()
      settle()
    }
    if app.buttons["more"].exists {
      app.buttons["more"].firstMatch.tap()
      settle()
      shot("4c-more-menu")
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.9)).tap()
      settle()
    }
    app.buttons["back"].firstMatch.tap()
    settle()
    shot("5-library-after")
    // Opened again: strokes and the held shape as stored (ink widths after a reload).
    let card = app.descendants(matching: .any)["notebook-New notebook"].firstMatch
    if card.exists {
      card.tap()
      settle()
      if app.buttons["write"].exists {
        app.buttons["write"].firstMatch.tap()
        settle()
      }
      shot("5b-reopened")
      app.buttons["back"].firstMatch.tap()
      settle()
    }
    // The seeded PDF: its slide-shaped pages, opened just for looking (Write to write on it).
    let pdf = app.descendants(matching: .any)["notebook-Lecture slides"].firstMatch
    if pdf.exists {
      pdf.tap()
      settle()
      shot("5c-pdf")
      if app.buttons["zoom-chip"].exists {
        app.buttons["zoom-chip"].firstMatch.tap()
        settle()
        shot("5d-pdf-fit")
      }
      app.buttons["back"].firstMatch.tap()
      settle()
    }
    if isPad {
      app.buttons["backups"].firstMatch.tap()
      settle()
      shot("6-backups")
      app.buttons["backups-done"].firstMatch.tap()
      settle()
      app.buttons["settings"].firstMatch.tap()
      settle()
      shot("7-settings")
    }
  }
}
