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

  /// On a phone the tools are folded behind one button: open it when the tool isn't showing.
  private func showTool(_ app: XCUIApplication, _ id: String) {
    if !app.buttons[id].exists, app.buttons["tools-button"].exists {
      app.buttons["tools-button"].firstMatch.tap()
      settle()
    }
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
        // The lasso picks the ellipse up on its own: its four dots show; the right one stretches it.
        showTool(app, "tool-lasso")
        if app.buttons["tool-lasso"].exists {
          app.buttons["tool-lasso"].firstMatch.tap()
          settle()
          app.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.44)), withVelocity: .slow, thenHoldForDuration: 0.05)
          settle()
          shot("4f2-shape-dots")
          app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.36))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.36)), withVelocity: .slow, thenHoldForDuration: 0.05)
          settle()
          shot("4f3-dot-dragged")
        }
      }
      app.buttons["pen-p1"].firstMatch.tap()
      settle()
    }
    // Typed text: the keyboard opens a box below what's written; the lasso tool puts it down.
    showTool(app, "tool-keyboard")
    if app.buttons["tool-keyboard"].exists {
      app.buttons["tool-keyboard"].firstMatch.tap()
      settle()
      let box = app.textViews["text-editor"].firstMatch
      if box.waitForExistence(timeout: 3) {
        box.tap()
        box.typeText("Sum of moments = 0\nReaction R = 12 kN")
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
