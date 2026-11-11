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

  private var liftedArea: CGRect? {
    var out = unionOf(pickedShapeRows)
    for t in texts where lasso.pickedTexts.contains(t.id) { out = joined(out, TextLook.frame(t)) }
    return out
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
    let area = liftedArea
    let picked = pickedShapeRows
    let pickedTexts = texts.filter { lasso.pickedTexts.contains($0.id) }
    guard !picked.isEmpty || !pickedTexts.isEmpty, let canvas, let pages else { return }
    lasso.overlayTicket += 1
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
    // Without actions: left to animate, the lifted shapes faded in while the page's had already gone.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lasso.shapeLayer.sublayers = textLayers + picked.map { (s: ShapeRow) -> CALayer in
      let l = CAShapeLayer()
      l.lineCap = .round
      l.lineJoin = .round
      trace(s, on: l, zoom: z)
      return l
    }
    lasso.shapeLayer.setAffineTransform(.identity)
    CATransaction.commit()
    pages.pages.under.shapes = shapes.filter { !lasso.pickedShapes.contains($0.id) }
    redrawPage(area)
  }

  /// Straight back on the page with nothing saved: a tap on a selection isn't an edit.
  func restoreLifted() {
    guard let pages, let shapesBefore = lasso.shapesBefore, let textsBefore = lasso.textsBefore else { return }
    pages.pages.under.shapes = shapesBefore
    pages.pages.under.texts = textsBefore
    redrawPage(liftedArea)
    carryShapes(.identity)
    if let only = pickedShapeRows.first, lasso.pickedShapes.count == 1 { showLive(only) }
  }

  private func trace(_ s: ShapeRow, on l: CAShapeLayer, zoom z: CGFloat) {
    let path = CGMutablePath()
    for line in s.geometry.paths(s.size) where line.count > 1 {
      path.addLines(between: line.map { CGPoint(x: CGFloat($0.x) * z, y: CGFloat($0.y) * z) })
    }
    l.path = path
    l.strokeColor = UIColor(argb: s.color).cgColor
    l.lineWidth = CGFloat(s.size) * z
    if let fill = s.fill, s.geometry.closed { l.fillColor = UIColor(argb: fill).cgColor } else { l.fillColor = UIColor.clear.cgColor }
    l.lineDashPattern = LineDash.pattern(s.line, width: CGFloat(s.size) * z)?.map { NSNumber(value: Double($0)) }
  }

  /// The carried shapes and text boxes follow the drag: moved, resized or turned by [t] (world units).
  func carryShapes(_ t: Affine) {
    guard let canvas, lasso.shapeLayer.sublayers?.isEmpty == false else { return }
    let z = canvas.zoomScale
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lasso.shapeLayer.setAffineTransform(CGAffineTransform(a: CGFloat(t.a), b: CGFloat(t.b), c: CGFloat(t.c), d: CGFloat(t.d), tx: CGFloat(t.tx) * z, ty: CGFloat(t.ty) * z))
    CATransaction.commit()
  }

  func showLive(_ s: ShapeRow) {
    guard let canvas, let l = lasso.shapeLayer.sublayers?.compactMap({ $0 as? CAShapeLayer }).first else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    trace(s, on: l, zoom: canvas.zoomScale)
    CATransaction.commit()
  }

  /// The overlay goes once the shapes are back on the page: a moment later, when the page has drawn
  /// them (taken away at once, there was a blink with nothing there).
  func dropShapes() {
    lasso.shapesBefore = nil
    lasso.textsBefore = nil
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

/// The eraser on shapes (Android's eraser takes whole shapes it passes over): PencilKit's eraser only
/// knows ink, so a watcher follows the eraser's touch and takes shapes off as it reaches them.
struct ShapeEraser {
  var watcher: StrokeWatcher?
  var before: [ShapeRow]?
  var textsBefore: [TextRow]?
}

extension NoteCanvas.Coordinator {
  func installShapeEraser(on v: PKCanvasView) {
    let w = StrokeWatcher(target: nil, action: nil)
    w.delegate = self
    w.began = { [weak self] t, _ in self?.eraseBegan(t) }
    w.moved = { [weak self] t, e in
      for s in e.coalescedTouches(for: t) ?? [t] { self?.eraseAt(s) }
    }
    w.ended = { [weak self] _ in self?.eraseEnded() }
    v.addGestureRecognizer(w)
    shapeEraser.watcher = w
  }

  private func eraseBegan(_ t: UITouch) {
    shapeEraser.before = nil
    guard parent.tool == .eraser, draws(t), claim(t) == nil else { return }
    shapeEraser.before = shapes
    eraseAt(t)
  }

  private func eraseAt(_ t: UITouch) {
    guard let canvas, shapeEraser.before != nil else { return }
    let q = t.location(in: canvas)
    let p = Pt(Float(q.x / canvas.zoomScale), Float(q.y / canvas.zoomScale))
    let reach = parent.eraser.size / 2
    // Text boxes go when the eraser passes over them, like a shape (Android's eraser takes them whole).
    let textHits = texts.filter { !$0.locked && TextLook.frame($0).insetBy(dx: -CGFloat(reach), dy: -CGFloat(reach)).contains(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))) }
    if !textHits.isEmpty {
      if shapeEraser.textsBefore == nil { shapeEraser.textsBefore = texts }
      let goneTexts = Set(textHits.map(\.id))
      setTexts(texts.filter { !goneTexts.contains($0.id) })
    }
    let hit = shapes.filter { s in
      guard !s.locked, let b = s.geometry.bounds(s.size), b.outset(reach).contains(p) else { return false }
      let r = reach + s.size / 2
      return s.geometry.paths(s.size).contains { line in
        line.count > 1 && (0..<(line.count - 1)).contains { Geo.distToSegment(p, line[$0], line[$0 + 1]) <= r }
      }
    }
    if hit.isEmpty { return }
    let gone = Set(hit.map(\.id))
    setShapes(shapes.filter { !gone.contains($0.id) })
  }

  private func eraseEnded() {
    if let tb = shapeEraser.textsBefore {
      shapeEraser.textsBefore = nil
      if tb != texts { registerTextsChange(from: tb, to: texts) }
    }
    guard let before = shapeEraser.before else { return }
    shapeEraser.before = nil
    let after = shapes
    if before == after { return }
    registerShapesChange(from: before, to: after)
  }

  /// One undo step between two lists of shapes (redo goes forward again).
  func registerShapesChange(from before: [ShapeRow], to after: [ShapeRow]) {
    canvas?.undoManager?.registerUndo(withTarget: self) { c in
      MainActor.assumeIsolated {
        c.clearSelection()
        c.setShapes(before)
        c.registerShapesChange(from: after, to: before)
        c.reportUndo()
      }
    }
    reportUndo()
  }
}
