import ImageIO
import TaliCore
import UIKit
import UniformTypeIdentifiers

/// The eraser on fills (Android's `erasesFill`, `rubFill`, `finishFillEdits`): a fill is erased apart
/// from its outline, whatever pens the eraser is set to. The stroke eraser takes the whole fill it
/// passes over; the precise one rubs out just where it passes. Locked fills are left alone.
extension NoteCanvas.Coordinator {
  /// Fills under the sweep from [a] to [b] go from the page, shown but not yet saved. True when one was under it.
  func eraseFills(from a: Pt, to b: Pt, reach: Float, rubbed: inout [String: CGContext]) -> Bool {
    var hit = false
    for fill in fills where !fill.picture.locked && Self.passesOver(fill, a, b, reach) {
      hit = true
      if parent.eraser.precise { rub(fill, a, b, reach, &rubbed) } else { showFills(fills.filter { $0.row.id != fill.row.id }) }
    }
    return hit
  }

  /// Whether the eraser, sweeping from [a] to [b] with [radius], passes over the coloured part of [fill].
  private static func passesOver(_ fill: FillPicture, _ a: Pt, _ b: Pt, _ radius: Float) -> Bool {
    let step = max(1, radius / 2)
    let n = Int(a.dist(b) / step) + 1
    let r = radius * 0.7
    for i in 0...n {
      let c = a + (b - a) * (Float(i) / Float(n))
      for o in [Pt(0, 0), Pt(r, 0), Pt(-r, 0), Pt(0, r), Pt(0, -r)] where fill.covers(c + o) { return true }
    }
    return false
  }

  /// The precise eraser clears the part of [fill] it sweeps over.
  private func rub(_ fill: FillPicture, _ a: Pt, _ b: Pt, _ radius: Float, _ rubbed: inout [String: CGContext]) {
    let w = fill.image.width, h = fill.image.height
    let cg: CGContext
    if let open = rubbed[fill.row.id] {
      cg = open
    } else {
      guard let fresh = FillPicture.bitmap(w, h) else { return }
      fresh.draw(fill.image, in: CGRect(x: 0, y: 0, width: w, height: h))
      rubbed[fill.row.id] = fresh
      cg = fresh
    }
    let rect = fill.row.rect
    let sx = CGFloat(w) / CGFloat(rect.width), sy = CGFloat(h) / CGFloat(rect.height)
    // The bitmap's first row is at the top; Core Graphics counts up from the bottom.
    func px(_ p: Pt) -> CGPoint {
      var x = CGFloat(p.x - rect.left) * sx, y = CGFloat(p.y - rect.top) * sy
      if fill.row.flipX { x = CGFloat(w) - x }
      if fill.row.flipY { y = CGFloat(h) - y }
      return CGPoint(x: x, y: CGFloat(h) - y)
    }
    cg.setBlendMode(.clear)
    cg.setLineCap(.round)
    cg.setLineWidth(2 * CGFloat(radius) * (sx + sy) / 2)
    let from = px(a), to = px(b)
    cg.move(to: from)
    cg.addLine(to: CGPoint(x: to.x + 0.01, y: to.y))
    cg.strokePath()
    guard let image = cg.makeImage(), let covered = FillPicture.covered(cg) else { return }
    showFills(fills.map { $0.row.id == fill.row.id ? FillPicture(row: fill.row, image: image, covered: covered) : $0 })
  }

  /// Shows [now] on the page without saving it (the stroke isn't over, or was called off).
  func showFills(_ now: [FillPicture]) {
    guard let pages else { return }
    pages.pages.under.fills = now
    pages.layer.setNeedsDisplay()
  }

  /// The eraser lifted: fills rubbed out are saved as new pictures (or go when nothing's left of
  /// them), fills taken whole go. [before] is the fills as the eraser found them.
  func finishFillErase(_ rubbed: [String: CGContext], from before: [FillPicture]) {
    guard let pages else { return }
    var after: [FillPicture] = []
    for fill in fills {
      guard rubbed[fill.row.id] != nil else {
        after.append(fill)
        continue
      }
      if !fill.covered.contains(true) { continue }
      var p = fill.picture
      p.file = String(p.file.prefix(FillRow.prefix.count + 9)) + UUID().uuidString.lowercased().prefix(12) + ".png"
      if FillPicture.write(fill.image, to: p.file) { after.append(fill.with(p)) }
    }
    // Back as it was, then the change is made (and saved) in one step.
    pages.pages.under.fills = before
    setFills(after)
  }
}

extension FillPicture {
  static func covered(_ cg: CGContext) -> [Bool]? {
    guard let data = cg.data else { return nil }
    let n = cg.width * cg.height
    let bytes = data.bindMemory(to: UInt8.self, capacity: n * 4)
    return (0..<n).map { bytes[$0 * 4 + 3] > 0 }
  }

  static func write(_ image: CGImage, to file: String) -> Bool {
    let url = AppFiles.folders.images.appendingPathComponent(file)
    guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(out, image, nil)
    return CGImageDestinationFinalize(out)
  }
}
