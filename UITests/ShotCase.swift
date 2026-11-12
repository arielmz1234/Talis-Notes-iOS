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

/// The screen's pixels, upright: the tests check what was drawn, not only that nothing failed.
struct Pixels {
  let width: Int
  let height: Int
  private let bytes: [UInt8]

  @MainActor init() {
    let shot = XCUIScreen.main.screenshot().image
    let format = UIGraphicsImageRendererFormat()
    format.scale = shot.scale
    let upright = UIGraphicsImageRenderer(size: shot.size, format: format).image { _ in shot.draw(in: CGRect(origin: .zero, size: shot.size)) }.cgImage!
    let w = upright.width, h = upright.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    data.withUnsafeMutableBytes { buffer in
      let space = CGColorSpace(name: CGColorSpace.sRGB)!
      let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      ctx.draw(upright, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    width = w
    height = h
    bytes = data
  }

  typealias Colour = (r: Int, g: Int, b: Int)

  func colour(_ x: Int, _ y: Int) -> Colour {
    let i = (y * width + x) * 4
    return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
  }

  func colour(x: CGFloat, y: CGFloat) -> Colour { colour(Int(x * CGFloat(width)), Int(y * CGFloat(height))) }

  /// Rows and [x] are fractions of the screen. Nil when hardly any pixel in the column matches.
  func span(x: CGFloat, rows: ClosedRange<CGFloat>, _ match: (Colour) -> Bool) -> ClosedRange<CGFloat>? {
    let cx = Int(x * CGFloat(width)), half = max(width / 200, 3)
    var top = Int.max, bottom = Int.min, count = 0
    for y in Int(rows.lowerBound * CGFloat(height))...Int(rows.upperBound * CGFloat(height)) {
      for px in (cx - half)...(cx + half) where match(colour(px, y)) {
        top = min(top, y)
        bottom = max(bottom, y)
        count += 1
      }
    }
    guard count > half else { return nil }
    return (CGFloat(top) / CGFloat(height))...(CGFloat(bottom + 1) / CGFloat(height))
  }

  /// How many separate stretches of matching pixels there are from [x0] to [x1] along the row
  /// between [rows] that has the most of them: the pieces of a level dotted or dashed line.
  /// Breaks narrower than [gap] (a fraction of the screen's width) don't count: a grid line showing through.
  func runs(rows: ClosedRange<CGFloat>, from x0: CGFloat, to x1: CGFloat, gap: CGFloat = 0, _ match: (Colour) -> Bool) -> Int {
    let xs = Int(x0 * CGFloat(width))...Int(x1 * CGFloat(width))
    var best = (count: 0, y: 0)
    for y in Int(rows.lowerBound * CGFloat(height))...Int(rows.upperBound * CGFloat(height)) {
      let count = xs.reduce(0) { $0 + (match(colour($1, y)) ? 1 : 0) }
      if count > best.count { best = (count, y) }
    }
    guard best.count > 0 else { return 0 }
    var runs = 0, off = Int.max
    for x in xs {
      if match(colour(x, best.y)) {
        if off > Int(gap * CGFloat(width)) { runs += 1 }
        off = 0
      } else if off != Int.max {
        off += 1
      }
    }
    return runs
  }

  func darkest(x: CGFloat, rows: ClosedRange<CGFloat>) -> Colour {
    let cx = Int(x * CGFloat(width))
    return (Int(rows.lowerBound * CGFloat(height))...Int(rows.upperBound * CGFloat(height))).map { colour(cx, $0) }.min { $0.r + $0.g + $0.b < $1.r + $1.g + $1.b }!
  }

  /// How many pixels match from [x0] to [x1] between [rows] (fractions of the screen).
  func count(rows: ClosedRange<CGFloat>, from x0: CGFloat, to x1: CGFloat, _ match: (Colour) -> Bool) -> Int {
    var n = 0
    for y in Int(rows.lowerBound * CGFloat(height))...Int(rows.upperBound * CGFloat(height)) {
      for x in Int(x0 * CGFloat(width))...Int(x1 * CGFloat(width)) where match(colour(x, y)) { n += 1 }
    }
    return n
  }
}
