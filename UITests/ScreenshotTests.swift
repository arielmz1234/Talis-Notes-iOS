import XCTest

/// Opens the app with sample notebooks and saves screenshots for review. CI runs this once per
/// device and setting (light/dark, Hebrew), passing SHOT_DIR and SHOT_TAG through the environment.
final class ScreenshotTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = true
  }

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
    let png = XCUIScreen.main.screenshot().pngRepresentation
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
    shot("4-notebook")
    app.buttons["back"].firstMatch.tap()
    settle()
    shot("5-library-after")
  }
}
