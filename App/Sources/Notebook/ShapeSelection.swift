import PencilKit
import TaliCore
import UIKit

/// Shapes in the lasso's selection: the page layer draws shapes under the writing, so these keep its
/// list and the database in step, and carry picked-up shapes in an overlay while they're dragged
/// (redrawing the page's tiles every frame would flicker).
extension NoteCanvas.Coordinator {
  /// The notebook's shapes as drawn now.
  var shapes: [ShapeRow] { pages?.pages.under.shapes ?? [] }

  var pickedShapeRows: [ShapeRow] { shapes.filter { lasso.pickedShapes.contains($0.id) } }

  /// Makes [new] the notebook's shapes: what changed is saved, what's gone is removed.
  func setShapes(_ new: [ShapeRow]) {
    guard let pages else { return }
    let old = pages.pages.under.shapes
    if old == new { return }
    let keep = Set(new.map(\.id))
    var before: [String: ShapeRow] = [:]
    for s in old { before[s.id] = s }
    do {
      for s in old where !keep.contains(s.id) { try parent.db.removeItem(s.id) }
      for s in new where before[s.id] != s { try parent.db.put(s.itemRow, in: parent.notebook.id) }
    } catch {
      CrashNote.log("saving shapes: \(error)")
    }
    pages.pages.under.shapes = new
    pages.layer.setNeedsDisplay()
    touch()
  }

  /// [s] moved, scaled, turned or mirrored by [m]; a scaled shape's line scales with it (Android's `transformed`).
  func moved(_ s: ShapeRow, by m: Affine) -> ShapeRow {
    var c = s
    c.geometry = s.geometry.transformed(m)
    c.size = max(s.size * m.scaleFactor, 0.5)
    return c
  }

  func unionOf(_ list: [ShapeRow]) -> CGRect? {
    var out: CGRect?
    for s in list {
      guard let b = s.geometry.bounds(s.size) else { continue }
      let r = CGRect(b)
      out = out.map { $0.union(r) } ?? r
    }
    return out
  }

  func joined(_ a: CGRect?, _ b: CGRect?) -> CGRect? {
    switch (a, b) {
    case let (a?, b?): a.union(b)
    case let (a?, nil): a
    case let (nil, b?): b
    default: nil
    }
  }

  /// Takes the picked shapes off the page and into the overlay, ready to be carried.
  func liftShapes() {
    lasso.shapesBefore = shapes
    lasso.textsBefore = texts
    let picked = pickedShapeRows
    let pickedTexts = texts.filter { lasso.pickedTexts.contains($0.id) }
    guard !picked.isEmpty || !pickedTexts.isEmpty, let canvas, let pages else { return }
    let z = canvas.zoomScale
    // Text boxes ride along as pictures of themselves at this zoom.
    let textLayers: [CALayer] = pickedTexts.map { t in
      let f = TextLook.frame(t)
      let l = CALayer()
      l.frame = CGRect(x: f.minX * z, y: f.minY * z, width: f.width * z, height: f.height * z)
      l.contentsScale = canvas.traitCollection.displayScale
      let format = UIGraphicsImageRendererFormat()
      format.scale = canvas.traitCollection.displayScale
      l.contents = UIGraphicsImageRenderer(size: l.frame.size, format: format).image { ctx in
        ctx.cgContext.scaleBy(x: z, y: z)
        TextLook.attributed(t).draw(with: CGRect(x: 0, y: 0, width: f.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
      }.cgImage
      return l
    }
    pages.pages.under.texts = texts.filter { !lasso.pickedTexts.contains($0.id) }
    lasso.shapeLayer.sublayers = textLayers + picked.map { (s: ShapeRow) -> CALayer in
      let l = CAShapeLayer()
      let path = CGMutablePath()
      for line in s.strokes {
        path.addLines(between: line.map { CGPoint(x: CGFloat($0.x) * z, y: CGFloat($0.y) * z) })
      }
      l.path = path
      l.strokeColor = UIColor(argb: s.inkColor).cgColor
      l.lineWidth = CGFloat(s.size) * z
      l.lineCap = .round
      l.lineJoin = .round
      if let fill = s.fill, s.geometry.closed { l.fillColor = UIColor(argb: fill).cgColor } else { l.fillColor = UIColor.clear.cgColor }
      return l
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lasso.shapeLayer.setAffineTransform(.identity)
    CATransaction.commit()
    pages.pages.under.shapes = shapes.filter { !lasso.pickedShapes.contains($0.id) }
    pages.layer.setNeedsDisplay()
  }

  /// The carried shapes follow the drag ([shift] in world units).
  func carryShapes(_ shift: CGAffineTransform) {
    guard let canvas, lasso.shapeLayer.sublayers?.isEmpty == false else { return }
    // (Shapes and text boxes alike.)
    let z = canvas.zoomScale
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lasso.shapeLayer.setAffineTransform(CGAffineTransform(translationX: shift.tx * z, y: shift.ty * z))
    CATransaction.commit()
  }

  /// The overlay goes once the shapes are back on the page.
  func dropShapes() {
    lasso.shapesBefore = nil
    lasso.textsBefore = nil
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lasso.shapeLayer.sublayers = nil
    lasso.shapeLayer.setAffineTransform(.identity)
    CATransaction.commit()
  }
}
