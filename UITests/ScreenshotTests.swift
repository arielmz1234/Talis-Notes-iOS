import XCTest

/// The tour CI has always taken: library, a new notebook, writing, the tools, reopening, a PDF.
@MainActor
final class ScreenshotTests: ShotCase {

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
