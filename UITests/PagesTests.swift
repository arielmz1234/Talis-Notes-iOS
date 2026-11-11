import XCTest

/// Pages and paper in a notebook: the paper menu and cards, her own papers, pulling up for a new
/// page, page numbers, the endless canvas, the page overview, dark paper and hiding the toolbars.
@MainActor
final class PagesTests: ShotCase {
  private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

  private func open(_ app: XCUIApplication, _ title: String) {
    let card = app.descendants(matching: .any)["notebook-\(title)"].firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 6), "no notebook \(title)")
    card.tap()
    settle()
    if app.buttons["write"].exists {
      app.buttons["write"].firstMatch.tap()
      settle()
    }
  }

  /// A segmented choice by its label (shown as a button or as text).
  private func tapLabel(_ app: XCUIApplication, _ label: String) {
    let b = app.buttons[label].firstMatch
    if b.exists { b.tap() } else { app.staticTexts[label].firstMatch.tap() }
    settle()
  }

  private func more(_ app: XCUIApplication) {
    app.buttons["more"].firstMatch.tap()
    settle()
  }

  private func closePopover(_ app: XCUIApplication) {
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.97)).tap()
    settle()
  }

  func testPapers() {
    continueAfterFailure = true
    XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
    let app = launch()
    settle()
    open(app, "Exam revision")
    more(app)
    shot("p1-more-menu")
    app.buttons["paper-more"].firstMatch.tap()
    settle()
    shot("p2-papers-open")
    for style in ["DOTS", "GRID", "ENGINEERING", "ISOMETRIC", "CORNELL", "RULED", "BLANK", "LINES"] {
      let tile = app.descendants(matching: .any)["paper-\(style)"].firstMatch
      if !tile.exists, app.buttons["paper-more"].exists {
        app.buttons["paper-more"].firstMatch.tap()
        settle()
      }
      guard tile.exists else {
        XCTFail("no paper \(style)")
        continue
      }
      tile.tap()
      settle()
      closePopover(app)
      shot("p3-paper-\(style)")
      more(app)
    }
    // The paper in use wears a pencil: tapping it again opens its card.
    app.descendants(matching: .any)["paper-LINES"].firstMatch.tap()
    settle()
    shot("p4-lines-card")
    tapLabel(app, "Bolder")
    settle()
    shot("p5-lines-bolder")
    app.buttons["paper-card-done"].firstMatch.tap()
    settle()
    shot("p6-page-bolder")
    // Dark paper: the page goes dark and the ink shows light, while it's stored as written.
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.56)))
    settle()
    more(app)
    tapLabel(app, "Dark paper")
    closePopover(app)
    shot("p6-dark-paper")
    more(app)
    tapLabel(app, "Dark paper")
    closePopover(app)
    // Her own paper: a grid with a margin line, half as strong.
    more(app)
    if !app.descendants(matching: .any)["paper-own"].exists { app.buttons["paper-more"].firstMatch.tap() }
    settle()
    app.descendants(matching: .any)["paper-own"].firstMatch.tap()
    settle()
    shot("p7-your-own")
    tapLabel(app, "Grid")
    let margin = app.switches.firstMatch
    if margin.exists { margin.tap() }
    settle()
    shot("p8-your-own-grid")
    app.buttons["save-paper"].firstMatch.tap()
    settle()
    shot("p9-her-paper")
    more(app)
    if !app.staticTexts["My grid"].exists, app.buttons["paper-more"].exists { app.buttons["paper-more"].firstMatch.tap() }
    settle()
    shot("p10-her-paper-in-menu")
    let mine = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'My grid'")).firstMatch
    if mine.exists {
      mine.press(forDuration: 1.0)
      settle()
      shot("p11-remove-her-paper")
    } else {
      XCTFail("her paper isn't in the menu")
    }
  }
}
