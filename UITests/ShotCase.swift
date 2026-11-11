import XCTest

/// Launches the app with sample notebooks and saves screenshots for review. CI runs the tests once
/// per device and setting (light/dark, Hebrew), passing SHOT_DIR and SHOT_TAG through the environment.
/// Each area of the app keeps its own test class on top of this one.
@MainActor
class ShotCase: XCTestCase {

  var tag: String { ProcessInfo.processInfo.environment["SHOT_TAG"] ?? "local" }

  func launch(_ extra: [String] = []) -> XCUIApplication {
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

  func shot(_ name: String) {
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

  func settle() { Thread.sleep(forTimeInterval: 1.2) }

  /// On a phone the tools are folded behind one button: open it when the tool isn't showing.
  func showTool(_ app: XCUIApplication, _ id: String) {
    if !app.buttons[id].exists, app.buttons["tools-button"].exists {
      app.buttons["tools-button"].firstMatch.tap()
      settle()
    }
  }

}
