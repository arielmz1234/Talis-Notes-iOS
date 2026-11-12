import PencilKit
import TaliCore
import UIKit

/// What's picked up from the page layer (shapes, text, pictures, fills, locked writing): these keep
/// the layer's lists and the database in step, and carry what's picked up in an overlay while it's
/// dragged (redrawing the page's tiles every frame would flicker).
extension NoteCanvas.Coordinator {
  /// The notebook's shapes as drawn now.
  var shapes: [ShapeRow] { pages?.pages.under.shapes ?? [] }

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
    let after = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    redrawPage(unionOf(old.filter { after[$0.id] != $0 } + new.filter { before[$0.id] != $0 }))
    touch()
  }

  /// Only there: redrawing every tile for one shape
  /// left the page blank for a moment.
  func redrawPage(_ area: CGRect?) {
    guard let pages, let area else { return }
    pages.layer.setNeedsDisplay(area.insetBy(dx: -4, dy: -4))
  }

  /// Takes what's picked up off the page and into the overlay, ready to be carried.
  func liftShapes() {
    guard let canvas, let pages else { return }
    let under = pages.pages.under
    lasso.lifted = under
    let picked = lasso.picked
    let upShapes = under.shapes.filter { picked.contains($0.id) }, upTexts = under.texts.filter { picked.contains($0.id) }
    let upPictures = under.pictures.filter { picked.contains($0.row.id) }, upFills = under.fills.filter { picked.contains($0.row.id) }
    let upInk = under.lockedInk.filter { picked.contains($0.id) }
    guard !(upShapes.isEmpty && upTexts.isEmpty && upPictures.isEmpty && upFills.isEmpty && upInk.isEmpty) else { return }
    lasso.overlayTicket += 1
    let z = canvas.zoomScale
    let scale = canvas.traitCollection.displayScale
    func placed(_ world: CGRect) -> CALayer {
      let l = CALayer()
      l.frame = CGRect(x: world.minX * z, y: world.minY * z, width: world.width * z, height: world.height * z)
      l.contentsScale = scale
      return l
    }
    var layers: [CALayer] = upPictures.filter { !$0.row.front }.map { pic in
      let l = placed(pic.rect)
      l.contents = pic.image
      return l
    }
    layers += upFills.map { fill in
      let l = placed(CGRect(fill.row.rect))
      l.contents = fill.image
      l.setAffineTransform(CGAffineTransform(scaleX: fill.row.flipX ? -1 : 1, y: fill.row.flipY ? -1 : 1))
      return l
    }
    layers += upShapes.map { (s: ShapeRow) -> CALayer in
      let l = CAShapeLayer()
      l.name = s.id
      l.lineCap = .round
      l.lineJoin = .round
      trace(s, on: l, zoom: z)
      return l
    }
    // Text boxes and locked writing ride along as pictures of themselves at this zoom.
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    layers += upTexts.map { t in
      let f = TextLook.frame(t)
      let l = placed(f)
      l.contents = UIGraphicsImageRenderer(size: l.frame.size, format: format).image { ctx in
        ctx.cgContext.scaleBy(x: z, y: z)
        var shown = t
        if parent.settings.dark { shown.color = DarkInk.onDarkPaper(t.color) }
        TextLook.attributed(shown).draw(with: CGRect(x: 0, y: 0, width: f.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
      }.cgImage
      return l
    }
    layers += upPictures.filter(\.row.front).map { pic in
      let l = placed(pic.rect)
      l.contents = pic.image
      return l
    }
    if !upInk.isEmpty {
      let drawing = PKDrawing(strokes: upInk.map { $0.pkStroke(mask: mask(for: $0)) })
      let box = drawing.bounds.insetBy(dx: -2, dy: -2)
      let l = placed(box)
      canvas.traitCollection.performAsCurrent { l.contents = drawing.image(from: box, scale: z * scale).cgImage }
      layers.append(l)
    }
    var left = under
    left.shapes.removeAll { picked.contains($0.id) }
    left.texts.removeAll { picked.contains($0.id) }
    left.pictures.removeAll { picked.contains($0.row.id) }
    left.fills.removeAll { picked.contains($0.row.id) }
    left.setLockedInk(under.lockedInk.filter { !picked.contains($0.id) }) { self.mask(for: $0) }
    // Without actions: left to animate, the lifted shapes faded in while the page's had already gone.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lasso.shapeLayer.sublayers = layers
    lasso.shapeLayer.setAffineTransform(.identity)
    CATransaction.commit()
    pages.pages.under = left
    redrawPage(lasso.bounds)
  }

  /// Straight back on the page with nothing saved: a tap on a selection isn't an edit.
  func restoreLifted() {
    guard let pages, let lifted = lasso.lifted else { return }
    lasso.lifted = nil
    pages.pages.under = lifted
    redrawPage(lasso.bounds)
    carryShapes(.identity)
  }

  private func trace(_ s: ShapeRow, on l: CAShapeLayer, zoom z: CGFloat) {
    let path = CGMutablePath()
    for line in s.strokes {
      path.addLines(between: line.map { CGPoint(x: CGFloat($0.x) * z, y: CGFloat($0.y) * z) })
    }
    l.path = path
    l.strokeColor = UIColor(argb: parent.settings.dark ? DarkInk.onDarkPaper(s.inkColor) : s.inkColor).cgColor
    l.lineWidth = CGFloat(s.size) * z
    if let fill = s.fill, s.geometry.closed { l.fillColor = UIColor(argb: fill).cgColor } else { l.fillColor = UIColor.clear.cgColor }
  }

  /// What's carried follows the drag: moved, resized or turned by [t] (world units).
  func carryShapes(_ t: Affine) {
    guard let canvas, lasso.shapeLayer.sublayers?.isEmpty == false else { return }
    let z = canvas.zoomScale
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lasso.shapeLayer.setAffineTransform(CGAffineTransform(a: CGFloat(t.a), b: CGFloat(t.b), c: CGFloat(t.c), d: CGFloat(t.d), tx: CGFloat(t.tx) * z, ty: CGFloat(t.ty) * z))
    CATransaction.commit()
  }

  /// The one shape carried, drawn as it is now (a dot of it is being dragged).
  func showLive(_ s: ShapeRow) {
    guard let canvas, let l = lasso.shapeLayer.sublayers?.compactMap({ $0 as? CAShapeLayer }).first(where: { $0.name == s.id }) else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    trace(s, on: l, zoom: canvas.zoomScale)
    CATransaction.commit()
  }

  /// The shapes carried, drawn [size] thick (the menu's thickness slider is moving).
  func showThickness(_ size: Float) {
    for var s in lasso.lifted?.shapes ?? [] where lasso.picked.contains(s.id) {
      s.size = size
      showLive(s)
    }
  }

  /// The overlay goes once what it carried is back on the page: a moment later, when the page has
  /// drawn it (taken away at once, there was a blink with nothing there).
  func dropShapes() {
    lasso.overlayTicket += 1
    let ticket = lasso.overlayTicket
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      guard let self, self.lasso.overlayTicket == ticket else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      self.lasso.shapeLayer.sublayers = nil
      self.lasso.shapeLayer.setAffineTransform(.identity)
      CATransaction.commit()
    }
  }
}
