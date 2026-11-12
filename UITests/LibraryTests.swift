import XCTest

/// The library and its cards: folders inside folders, the + card, picking several, mist, the
/// gliding highlight, Recently deleted, Settings and the tour.
@MainActor
final class LibraryTests: ShotCase {
  private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

  override func setUp() {
    super.setUp()
    continueAfterFailure = true
    XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
  }

  /// On a phone the sidebar is a drawer: open it first.
  private func sidebar(_ app: XCUIApplication) {
    if app.buttons["drawer"].exists && !app.buttons["shelf-all"].isHittable {
      app.buttons["drawer"].tap()
      settle()
    }
  }

  private func tapSidebar(_ app: XCUIApplication, _ id: String) {
    sidebar(app)
    let row = app.descendants(matching: .any)[id].firstMatch
    XCTAssert(row.waitForExistence(timeout: 3), "\(id) is in the sidebar")
    row.tap()
    settle()
  }

  /// Holds [id] until its menu shows [item]; a slow simulator sometimes misses the first hold.
  private func hold(_ app: XCUIApplication, _ id: String, for item: String) -> XCUIElement {
    let menuItem = app.buttons[item].firstMatch
    for _ in 0..<2 where !menuItem.exists {
      app.descendants(matching: .any)[id].firstMatch.press(forDuration: 1.0)
      _ = menuItem.waitForExistence(timeout: 4)
    }
    return menuItem
  }

  func testFolders() {
    let app = launch()
    settle()
    shot("lib-1-library")
    tapSidebar(app, "sidebar-folder-Statics")
    shot("lib-2-folder")
    app.buttons["new-folder-tile"].firstMatch.tap()
    settle()
    app.typeText("Beams")
    shot("lib-3-new-folder-card")
    app.buttons["folder-create"].firstMatch.tap()
    Thread.sleep(forTimeInterval: 0.18)
    shot("lib-4-folder-arriving")
    settle()
    shot("lib-5-folder-with-folder")
    app.descendants(matching: .any)["folder-Beams"].firstMatch.tap()
    settle()
    shot("lib-6-inside-path-empty")
    tapSidebar(app, "sidebar-folder-Calculus")
    Thread.sleep(forTimeInterval: 0.08)
    shot("lib-7-glide-moving")
    settle()
    shot("lib-8-calculus")
    sidebar(app)
    let move = hold(app, "sidebar-folder-Statics", for: "menu-move-folder")
    shot("lib-9-folder-menu")
    if move.exists {
      move.tap()
      settle()
      shot("lib-10-move-folder")
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
      settle()
    }
    sidebar(app)
    shot("lib-35-before-folder-hold")
    let delete = hold(app, "sidebar-folder-Calculus", for: "menu-delete-folder")
    if delete.exists {
      delete.tap()
      settle()
      shot("lib-30-delete-folder")
      app.buttons["confirm"].firstMatch.tap()
      Thread.sleep(forTimeInterval: 0.15)
      shot("lib-31-folder-mist")
      settle()
      shot("lib-32-folder-gone")
    }
  }

  func testAddPickAndMist() {
    let app = launch()
    settle()
    app.buttons["sort"].firstMatch.tap()
    settle()
    app.buttons["sort-NAME"].firstMatch.tap()
    settle()
    shot("lib-34-sort-stays-open")
    app.buttons["sort-EDITED"].firstMatch.tap()
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
    settle()
    app.swipeUp()
    settle()
    shot("lib-36-scrolled")
    app.swipeDown()
    settle()
    app.buttons["add"].firstMatch.tap()
    Thread.sleep(forTimeInterval: 0.6)
    shot("lib-11-add-card")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
    settle()
    app.buttons["select"].firstMatch.tap()
    settle()
    app.descendants(matching: .any)["notebook-Truss problems"].firstMatch.tap()
    app.descendants(matching: .any)["notebook-Lab report"].firstMatch.tap()
    settle()
    shot("lib-12-picking")
    app.buttons["pick-delete"].firstMatch.tap()
    settle()
    shot("lib-13-delete-picked")
    app.buttons["confirm"].firstMatch.tap()
    Thread.sleep(forTimeInterval: 0.15)
    shot("lib-14-mist")
    Thread.sleep(forTimeInterval: 0.15)
    shot("lib-15-mist-later")
    settle()
    shot("lib-16-after-delete")
    tapSidebar(app, "shelf-trash")
    shot("lib-17-recently-deleted")
    app.descendants(matching: .any)["notebook-Lab report"].firstMatch.tap()
    settle()
    shot("lib-18-trash-card")
    app.buttons["restore"].firstMatch.tap()
    settle()
    app.descendants(matching: .any)["notebook-Truss problems"].firstMatch.press(forDuration: 0.8)
    settle()
    shot("lib-33-trash-hold")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
    settle()
    app.buttons["empty-trash"].firstMatch.tap()
    settle()
    shot("lib-19-empty-trash")
  }

  func testSettingsAndTour() {
    let app = launch()
    settle()
    tapSidebar(app, "settings")
    shot("lib-20-settings")
    app.buttons["colours-PEACH"].firstMatch.tap()
    Thread.sleep(forTimeInterval: 0.06)
    shot("lib-21-ring-moving")
    settle()
    app.descendants(matching: .any)["option-DARK"].firstMatch.tap()
    Thread.sleep(forTimeInterval: 0.06)
    shot("lib-22-pill-moving")
    settle()
    shot("lib-23-settings-peach-dark")
    app.buttons["colours-LILAC"].firstMatch.tap()
    app.descendants(matching: .any)["option-LIGHT"].firstMatch.tap()
    settle()
    app.buttons["take-tour"].firstMatch.tap()
    settle()
    walk(app, steps: 7, name: "lib-24-tour")
    XCTAssertFalse(app.buttons["tour-next"].exists, "Start writing closes the tour after its seventh step")
    app.buttons["add"].firstMatch.tap()
    settle()
    app.buttons["add-notebook"].firstMatch.tap()
    settle()
    shot("lib-28-new-notebook")
  }

  func testTips() {
    let app = launch()
    settle()
    tapSidebar(app, "settings")
    app.buttons["tips-and-tricks"].firstMatch.tap()
    settle()
    walk(app, steps: 15, name: "lib-50-tips")
    XCTAssertFalse(app.buttons["tour-next"].exists, "Done closes the tips after the fifteenth")
  }

  /// Her own paper made from the new-notebook card: the card comes back with it chosen, the notebook
  /// is made on it, its library card shows it, and the next new notebook starts on it.
  func testHerPapers() {
    let app = launch()
    settle()
    app.buttons["add"].firstMatch.tap()
    settle()
    app.buttons["add-notebook"].firstMatch.tap()
    settle()
    if !app.descendants(matching: .any)["paper-own"].exists { app.buttons["paper-more"].firstMatch.tap() }
    settle()
    app.descendants(matching: .any)["paper-own"].firstMatch.tap()
    settle()
    let name = app.textFields["paper-name"].firstMatch
    XCTAssert(name.waitForExistence(timeout: 3), "Your own opens the paper card")
    for label in ["Grid", "Heavy"] {
      let b = app.buttons[label].firstMatch
      if b.exists { b.tap() } else { app.staticTexts[label].firstMatch.tap() }
    }
    if app.switches.firstMatch.exists { app.switches.firstMatch.tap() }
    settle()
    shot("lib-59-her-paper-heavy")
    name.tap()
    name.typeText("Margins")
    settle()
    shot("lib-60-her-paper-card")
    app.buttons["save-paper"].firstMatch.tap()
    settle()
    let mine = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Margins'")).firstMatch
    XCTAssert(mine.waitForExistence(timeout: 3), "the new-notebook card offers her paper")
    XCTAssert(mine.isSelected, "her new paper is the one chosen")
    shot("lib-61-new-notebook-her-paper")
    app.buttons["create"].firstMatch.tap()
    settle()
    if app.buttons["write"].exists {
      app.buttons["write"].firstMatch.tap()
      settle()
    }
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.45)))
    settle()
    app.buttons["back"].firstMatch.tap()
    settle()
    shot("lib-62-her-paper-card-picture")
    app.buttons["add"].firstMatch.tap()
    settle()
    app.buttons["add-notebook"].firstMatch.tap()
    settle()
    let again = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Margins'")).firstMatch
    XCTAssert(again.waitForExistence(timeout: 3) && again.isSelected, "the next notebook starts on her paper")
    shot("lib-63-next-starts-on-her-paper")
  }

  /// Shoots each of a steps card's [steps] a moment into its drawing, then taps through the last.
  private func walk(_ app: XCUIApplication, steps: Int, name: String) {
    for i in 1...steps {
      if i > 1 { app.buttons["tour-next"].firstMatch.tap() }
      Thread.sleep(forTimeInterval: 1.5)
      shot(String(format: "%@-%02d", name, i))
    }
    app.buttons["tour-next"].firstMatch.tap()
    settle()
  }

  func testPortrait() throws {
    try XCTSkipUnless(isPad, "the phone is always upright")
    XCUIDevice.shared.orientation = .portrait
    let app = launch()
    settle()
    shot("lib-40-portrait")
    tapSidebar(app, "sidebar-folder-Statics")
    shot("lib-41-portrait-folder")
    app.buttons["add"].firstMatch.tap()
    Thread.sleep(forTimeInterval: 0.6)
    shot("lib-42-portrait-add")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
    settle()
    tapSidebar(app, "settings")
    shot("lib-43-portrait-settings")
  }

  func testEmptyLibrary() {
    let app = XCUIApplication()
    var args = ["-uitest"]
    let env = ProcessInfo.processInfo.environment
    args.append(env["SHOT_DARK"] == "1" ? "-dark" : "-light")
    if let lang = env["SHOT_LANG"], !lang.isEmpty { args += ["-AppleLanguages", "(\(lang))", "-AppleLocale", lang] }
    app.launchArguments = args
    app.launch()
    settle()
    shot("lib-29-empty")
  }
}
