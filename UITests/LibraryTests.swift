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
