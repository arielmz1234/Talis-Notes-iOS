import XCTest

/// Opens the app with sample notebooks and saves screenshots for review. CI runs this once per
/// device and setting (light/dark, Hebrew), passing SHOT_DIR and SHOT_TAG through the environment.
@MainActor
final class ScreenshotTests: XCTestCase {

  private var tag: String { ProcessInfo.processInfo.environment["SHOT_TAG"] ?? "local" }

  private func launch(_ extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    var args = ["-uitest", "-seed"]
    let env = ProcessInfo.processInfo.environment
    if env["SHOT_DARK"] == "1" { args.append("-dark") } else { args.append("-light") }
    if let lang = env["SHOT_LANG"], !lang.isEmpty {
      args += ["-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
    }
    app.launchArguments = args + extra
    app.launch()
    return app
  }

  private func shot(_ name: String) {
    // The screenshot's image carries its orientation; draw it upright so landscape shots aren't sideways.
    let image = XCUIScreen.main.screenshot().image
    let upright = UIGraphicsImageRenderer(size: image.size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = image.scale; return f }())
      .image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    let png = upright.pngData() ?? XCUIScreen.main.screenshot().pngRepresentation
    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
    attachment.name = "\(tag)-\(name)"
    attachment.lifetime = .keepAlways
    add(attachment)
    if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"], !dir.isEmpty {
      try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
      try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(tag)-\(name).png"))
    }
  }

  private func settle() { Thread.sleep(forTimeInterval: 1.2) }

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
    settle()
    shot("4-notebook")
    // The pen's panel with its thickness slider (glass on iOS 26).
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
    shot("4b-pen-panel")
    app.buttons["pen-p1"].firstMatch.tap()
    settle()
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
