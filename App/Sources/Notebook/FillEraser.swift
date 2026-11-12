import ImageIO
import TaliCore
import UIKit
import UniformTypeIdentifiers

/// Fills the eraser is working on in this stroke.
struct FillErasing {
  /// The fills before the stroke began, and where the eraser last was.
  var before: [FillPicture]?
  var last: Pt?
  /// Fills being rubbed out: their pictures as they are now, not yet saved.
  var rubbed: [String: CGContext] = [:]
}

/// The eraser on fills (Android's `erasesFill`, `rubFill`, `finishFillEdits`): a fill is erased apart
/// from its outline. The stroke eraser takes the whole fill it passes over; the precise one rubs out
/// just where it passes. Locked fills are left alone. One undo step, with whatever else the stroke erased.
extension NoteCanvas.Coordinator {
  func eraseFills(at p: Pt, reach: Float) {
    let a = shapeEraser.fills.last ?? p
    shapeEraser.fills.last = p
    for fill in fills where !fill.picture.locked && Self.passesOver(fill, a, p, reach) {
      if shapeEraser.fills.before == nil { shapeEraser.fills.before = fills }
      if parent.eraser.precise { rub(fill, a, p, reach) } else { showFills(fills.filter { $0.row.id != fill.row.id }) }
    }
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
  private func rub(_ fill: FillPicture, _ a: Pt, _ b: Pt, _ radius: Float) {
    let w = fill.image.width, h = fill.image.height
    let cg: CGContext
    if let open = shapeEraser.fills.rubbed[fill.row.id] {
      cg = open
    } else {
      guard let fresh = FillPicture.bitmap(w, h) else { return }
      fresh.draw(fill.image, in: CGRect(x: 0, y: 0, width: w, height: h))
      shapeEraser.fills.rubbed[fill.row.id] = fresh
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

  /// Shows [now] on the page without saving it (the stroke isn't over).
  private func showFills(_ now: [FillPicture]) {
    guard let pages else { return }
    pages.pages.under.fills = now
    pages.layer.setNeedsDisplay()
  }

  /// The eraser lifted: fills rubbed out are saved as new pictures (or go when nothing's left of
  /// them), fills taken whole go, as one undo step.
  func finishFillErase() {
    let work = shapeEraser.fills
    shapeEraser.fills = FillErasing()
    guard let before = work.before, let pages else { return }
    var after: [FillPicture] = []
    for fill in fills {
      guard work.rubbed[fill.row.id] != nil else {
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
    if before.map(\.row) == after.map(\.row) {
      pages.layer.setNeedsDisplay()
      return
    }
    setFills(after)
    registerFillsChange(from: before, to: after)
  }

  private func registerFillsChange(from before: [FillPicture], to after: [FillPicture]) {
    canvas?.undoManager?.registerUndo(withTarget: self) { c in
      MainActor.assumeIsolated {
        c.clearSelection()
        c.setFills(before)
        c.registerFillsChange(from: after, to: before)
        c.reportUndo()
      }
    }
    reportUndo()
  }
}

extension FillPicture {
  /// Which cells of the picture drawn in [cg] are coloured.
  static func covered(_ cg: CGContext) -> [Bool]? {
    guard let data = cg.data else { return nil }
    let n = cg.width * cg.height
    let bytes = data.bindMemory(to: UInt8.self, capacity: n * 4)
    return (0..<n).map { bytes[$0 * 4 + 3] > 0 }
  }

  /// Saves [image] as [file] in the app's images folder.
  static func write(_ image: CGImage, to file: String) -> Bool {
    let url = AppFiles.folders.images.appendingPathComponent(file)
    guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(out, image, nil)
    return CGImageDestinationFinalize(out)
  }
}
