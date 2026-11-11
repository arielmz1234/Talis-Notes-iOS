import PencilKit
import TaliCore
import UIKit

/// What the lasso is doing and what it has picked up.
struct LassoState {
  /// The lasso's own touches (a watcher like hold-to-shape's: a pan recogniser was allowed to begin
  /// on PKCanvasView but never began).
  var pan: StrokeWatcher?
  var hold: UILongPressGestureRecognizer?
  /// The loop being drawn, in world units.
  var loop: [Pt] = []
  /// The ids of the strokes picked up, and their bounds (world units).
  var picked: Set<String> = []
  /// The shapes picked up (ids), shown while moving in [shapeLayer] and stored again on letting go.
  var pickedShapes: Set<String> = []
  var shapesBefore: [ShapeRow]?
  /// Text boxes picked up, the same way.
  var pickedTexts: Set<String> = []
  var textsBefore: [TextRow]?
  let shapeLayer = CALayer()
  var bounds: CGRect?
  /// Moving what's picked up: where the drag began and the drawing before it.
  var moving = false
  var moveStart: CGPoint = .zero
  var before: PKDrawing?
  /// Where a hold offered Paste (world units).
  var pasteAt: CGPoint?
  var lastPicked = 0
  /// Where the lasso's touch last was (world units).
  var lastAt: CGPoint = .zero
  let loopLayer = CAShapeLayer()
  let frameLayer = CAShapeLayer()
}

/// Strokes copied or cut, carried across notebooks (Android's `Clipboard`), in world units.
@MainActor
enum InkClipboard {
  static var strokes: [InkStroke] = []
  static var shapes: [ShapeRow] = []
  static var isEmpty: Bool { strokes.isEmpty && shapes.isEmpty }
}

/// The lasso and the selection menu (Android's `NoteCanvasView` lasso, `finishLasso`, the selection
/// menu's folded buttons and hold-to-paste): a dashed loop picks up whatever it touches, a dashed
/// frame shows it, a drag inside the frame moves it, and the menu copies, cuts, duplicates, boxes
/// or deletes it. Holding still on the page with something copied offers Paste there.
extension NoteCanvas.Coordinator: UIGestureRecognizerDelegate {
  static let pasteHold: TimeInterval = 0.6
  static let duplicateOffset: CGFloat = 24
  static let frameGap: CGFloat = 12

  func installSelection(on v: PKCanvasView) {
    let pan = StrokeWatcher(target: nil, action: nil)
    pan.delegate = self
    pan.began = { [weak self] t, _ in self?.lassoStep(.began, t) }
    pan.moved = { [weak self] t, e in
      for s in e.coalescedTouches(for: t) ?? [t] { self?.lassoStep(.changed, s) }
    }
    pan.ended = { [weak self] cancelled in self?.lassoStep(cancelled ? .cancelled : .ended, nil) }
    pan.isEnabled = false
    v.addGestureRecognizer(pan)
    lasso.pan = pan
    // While the lasso is on, one finger or the pencil draws the loop; two fingers still scroll.
    v.panGestureRecognizer.require(toFail: pan)
    let hold = UILongPressGestureRecognizer(target: self, action: #selector(pasteHold(_:)))
    hold.minimumPressDuration = Self.pasteHold
    hold.allowableMovement = 8
    hold.delegate = self
    v.addGestureRecognizer(hold)
    lasso.hold = hold
    for layer in [lasso.loopLayer, lasso.frameLayer] {
      layer.fillColor = UIColor.clear.cgColor
      layer.lineWidth = 1.5
      layer.lineDashPattern = layer === lasso.loopLayer ? [5, 5] : [6, 4]
      layer.zPosition = 10
      v.layer.addSublayer(layer)
    }
    lasso.shapeLayer.zPosition = 9
    v.layer.addSublayer(lasso.shapeLayer)
  }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    // The hold runs alongside everything; the lasso alongside PencilKit's own recognisers (scrolling
    // waits for it to fail instead).
    // The hold and every touch watcher (hold-to-shape, the shape eraser) run alongside everything.
    if g === lasso.hold || g === textEdit.tap || (g is StrokeWatcher && g !== lasso.pan) { return true }
    if g === lasso.pan { return other !== canvas?.panGestureRecognizer }
    return false
  }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    // A tap inside the text box being typed in is the text box's own (placing the cursor), not "done".
    if g === textEdit.tap, let v = textEdit.view, let hit = touch.view, hit === v || hit.isDescendant(of: v) { return false }
    return true
  }

  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    if g === lasso.hold { return !InkClipboard.isEmpty && !parent.viewOnly }
    return true
  }

  private var accent: UIColor { UIColor(argb: Int32(bitPattern: 0xFF7A_4ED6)) }

  private func world(_ g: UIGestureRecognizer) -> CGPoint {
    guard let canvas else { return .zero }
    let p = g.location(in: canvas)  // content coordinates (the scroll view's bounds origin is its offset)
    return CGPoint(x: p.x / canvas.zoomScale, y: p.y / canvas.zoomScale)
  }

  // MARK: Drawing the loop and moving

  /// One step of the lasso's touch: [t] is nil when it ends (it ends where it last was).
  func lassoStep(_ phase: UIGestureRecognizer.State, _ t: UITouch?) {
    guard let canvas else { return }
    if let t {
      let q = t.location(in: canvas)
      lasso.lastAt = CGPoint(x: q.x / canvas.zoomScale, y: q.y / canvas.zoomScale)
    }
    let p = lasso.lastAt
    switch phase {
    case .began:
      let pad = 8 / canvas.zoomScale
      if let b = lasso.bounds, b.insetBy(dx: -pad, dy: -pad).contains(p) {
        lasso.moving = true
        lasso.moveStart = p
        lasso.before = canvas.drawing
        liftShapes()
        parent.onSelection(nil)
      } else {
        clearSelection()
        lasso.loop = [Pt(Float(p.x), Float(p.y))]
      }
    case .changed:
      if lasso.moving, let before = lasso.before {
        let shift = CGAffineTransform(translationX: p.x - lasso.moveStart.x, y: p.y - lasso.moveStart.y)
        loading = true
        canvas.drawing = PKDrawing(strokes: before.strokes.enumerated().map { i, s in
          guard i < stored.count, lasso.picked.contains(stored[i].stroke.id) else { return s }
          var m = s
          m.transform = s.transform.concatenating(shift)
          return m
        })
        loading = false
        if let b = lasso.bounds { drawFrame(b.applying(shift)) }
        carryShapes(shift)
      } else {
        lasso.loop.append(Pt(Float(p.x), Float(p.y)))
        drawLoop()
      }
    case .ended, .cancelled, .failed:
      if lasso.moving {
        lasso.moving = false
        let dx = p.x - lasso.moveStart.x, dy = p.y - lasso.moveStart.y
        let shapesBefore = lasso.shapesBefore ?? shapes
        let textsBefore = lasso.textsBefore ?? texts
        if let before = lasso.before, abs(dx) + abs(dy) > 0.5 {
          let movedDrawing = canvas.drawing
          record(before, shapes: shapesBefore, texts: textsBefore)
          sync(movedDrawing)
          let by = Affine.translate(Float(dx), Float(dy))
          setShapes(shapesBefore.map { lasso.pickedShapes.contains($0.id) ? moved($0, by: by) : $0 })
          setTexts(textsBefore.map { t in
            guard lasso.pickedTexts.contains(t.id) else { return t }
            var c = t
            c.x += Float(dx)
            c.y += Float(dy)
            return c
          })
          lasso.bounds = lasso.bounds?.offsetBy(dx: dx, dy: dy)
          reportUndo()
        } else {
          setShapes(shapesBefore)
          setTexts(textsBefore)
        }
        dropShapes()
        lasso.before = nil
        redrawSelection()
      } else if phase == .cancelled {
        // A second finger came down: it's a pinch or scroll, not a loop.
        lasso.loop = []
        lasso.loopLayer.path = nil
      } else {
        finishLoop()
      }
    default: break
    }
  }

  /// Picks up whatever the loop touches (Android's `Lasso.touchesPath`: a stroke counts if any of it
  /// is inside or it crosses the loop's edge).
  private func finishLoop() {
    let loop = lasso.loop
    lasso.loop = []
    lasso.loopLayer.path = nil
    if ProcessInfo.processInfo.arguments.contains("-uitest") { parent.onHint("lasso \(loop.count) points") }
    guard loop.count > 2 else { return }
    var picked = Set<String>()
    var bounds: CGRect?
    for (_, s) in stored {
      let pts = s.inputs.points.map { Pt($0.x, $0.y) }
      guard let r = s.inputs.bounds, Rect.around(loop).map({ $0.outset(s.size).intersects(r) }) ?? false else { continue }
      if Lasso.touchesPath(pts, loop) {
        picked.insert(s.id)
        let b = CGRect(s.bounds)
        bounds = bounds.map { $0.union(b) } ?? b
      }
    }
    var pickedShapes = Set<String>()
    let loopBox = Rect.around(loop)
    for sh in shapes where !sh.locked {
      guard let r = sh.geometry.bounds(sh.size), loopBox.map({ $0.intersects(r) }) ?? false else { continue }
      if sh.geometry.paths(sh.size).contains(where: { $0.count > 1 && Lasso.touchesPath($0, loop) }) {
        pickedShapes.insert(sh.id)
        let b = CGRect(r)
        bounds = bounds.map { $0.union(b) } ?? b
      }
    }
    var pickedTexts = Set<String>()
    for t in texts where !t.locked {
      let f = TextLook.frame(t)
      let r = Rect(Float(f.minX), Float(f.minY), Float(f.maxX), Float(f.maxY))
      if Lasso.touchesRect(r, loop) {
        pickedTexts.insert(t.id)
        bounds = bounds.map { $0.union(f) } ?? f
      }
    }
    lasso.picked = picked
    lasso.pickedShapes = pickedShapes
    lasso.pickedTexts = pickedTexts
    lasso.bounds = picked.isEmpty && pickedShapes.isEmpty && pickedTexts.isEmpty ? nil : bounds
    if ProcessInfo.processInfo.arguments.contains("-uitest") { parent.onHint("lasso \(loop.count) points, \(picked.count + pickedShapes.count) picked") }
    lasso.lastPicked = picked.count + pickedShapes.count
    if lasso.bounds != nil { UISelectionFeedbackGenerator().selectionChanged() }
    redrawSelection()
  }

  func clearSelection() {
    lasso.picked = []
    lasso.pickedShapes = []
    lasso.pickedTexts = []
    lasso.bounds = nil
    lasso.loop = []
    lasso.loopLayer.path = nil
    lasso.frameLayer.path = nil
    parent.onSelection(nil)
  }

  private func drawLoop() {
    guard let canvas, let first = lasso.loop.first else { return }
    let z = canvas.zoomScale
    let path = CGMutablePath()
    path.move(to: CGPoint(x: CGFloat(first.x) * z, y: CGFloat(first.y) * z))
    for p in lasso.loop.dropFirst() { path.addLine(to: CGPoint(x: CGFloat(p.x) * z, y: CGFloat(p.y) * z)) }
    lasso.loopLayer.strokeColor = accent.cgColor
    lasso.loopLayer.path = path
  }

  private func drawFrame(_ b: CGRect) {
    guard let canvas else { return }
    let z = canvas.zoomScale
    let r = CGRect(x: b.minX * z, y: b.minY * z, width: b.width * z, height: b.height * z).insetBy(dx: -8, dy: -8).integral.insetBy(dx: 0.5, dy: 0.5)
    lasso.frameLayer.strokeColor = accent.cgColor
    lasso.frameLayer.path = UIBezierPath(roundedRect: r, cornerRadius: 6).cgPath
  }

  func redrawSelection() {
    if !lasso.loop.isEmpty { drawLoop() }
    guard let b = lasso.bounds else {
      lasso.frameLayer.path = nil
      return
    }
    drawFrame(b)
    reportSelection()
  }

  func reportSelection() {
    guard let canvas else { return }
    guard let b = lasso.bounds, !lasso.moving else { return }
    let z = canvas.zoomScale
    let content = CGRect(x: b.minX * z, y: b.minY * z, width: b.width * z, height: b.height * z).insetBy(dx: -8, dy: -8)
    parent.onSelection(canvas.convert(content, to: nil))
  }

  // MARK: The menu's actions

  private var pickedStrokes: [InkStroke] { stored.map(\.stroke).filter { lasso.picked.contains($0.id) } }

  /// Makes this change one undo step: going back restores [before].
  /// Shapes are part of the step too: [beforeShapes] (by default the shapes as they are now) come back with it.
  private func record(_ before: PKDrawing, shapes beforeShapes: [ShapeRow]? = nil, texts beforeTexts: [TextRow]? = nil) {
    let shapesThen = beforeShapes ?? shapes
    let textsThen = beforeTexts ?? texts
    canvas?.undoManager?.registerUndo(withTarget: self) { coord in
      MainActor.assumeIsolated {
        guard let canvas = coord.canvas else { return }
        let now = canvas.drawing
        coord.clearSelection()
        coord.record(now, shapes: coord.shapes, texts: coord.texts)
        canvas.drawing = before
        coord.setShapes(shapesThen)
        coord.setTexts(textsThen)
        coord.reportUndo()
      }
    }
  }

  func copySelection() {
    InkClipboard.strokes = pickedStrokes
    InkClipboard.shapes = pickedShapeRows
    parent.onHint(L("copied_hold_anywhere_to_paste_it"))
  }

  func cutSelection() {
    InkClipboard.strokes = pickedStrokes
    InkClipboard.shapes = pickedShapeRows
    deleteSelection()
    parent.onHint(L("cut_hold_anywhere_to_paste_it_2"))
  }

  func deleteSelection() {
    guard let canvas, lasso.bounds != nil else { return }
    let before = canvas.drawing
    let keep = before.strokes.enumerated().filter { i, _ in i >= stored.count || !lasso.picked.contains(stored[i].stroke.id) }.map(\.element)
    let gone = lasso.pickedShapes
    let goneTexts = lasso.pickedTexts
    clearSelection()
    record(before)
    canvas.drawing = PKDrawing(strokes: keep)
    setShapes(shapes.filter { !gone.contains($0.id) })
    setTexts(texts.filter { !goneTexts.contains($0.id) })
    reportUndo()
  }

  /// Copies a little down and to the right, and picks the copies up instead (Android: 24 units).
  func duplicateSelection() {
    let copies = add(pickedStrokes, shapes: pickedShapeRows, offset: CGPoint(x: Self.duplicateOffset, y: Self.duplicateOffset))
    select(copies.strokes, shapes: copies.shapes)
  }

  /// A rectangle round what's picked up, drawn with the pen in use, and joining the selection.
  func boxSelection() {
    guard let b = lasso.bounds else { return }
    let pen = currentPen
    let gap = Self.frameGap + CGFloat(pen.size) / 2
    let r = b.insetBy(dx: -gap, dy: -gap)
    // Corners repeated so PencilKit's curve keeps them sharp.
    let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY)]
    var pts: [InkInput] = []
    var t: Float = 0
    for p in corners {
      for _ in 0..<3 {
        pts.append(InkInput(x: Float(p.x), y: Float(p.y), t: t, pressure: 0.5))
        t += 0.004
      }
    }
    let box = InkStroke(id: newId(), z: 0, pen: pen.type, color: pen.inkColor, size: pen.size, inputs: InkInputs(points: pts, tool: .stylus))
    let keepShapes = pickedShapeRows
    let added = add([box], offset: .zero)
    select(pickedStrokes + added.strokes, shapes: keepShapes)
  }

  /// Adds copies of [strokes] and [newShapes] moved by [offset] with new ids, as one undo step; returns them.
  @discardableResult
  private func add(_ strokes: [InkStroke], shapes newShapes: [ShapeRow] = [], offset: CGPoint) -> (strokes: [InkStroke], shapes: [ShapeRow]) {
    guard let canvas, !strokes.isEmpty || !newShapes.isEmpty else { return ([], []) }
    let before = canvas.drawing
    var copies: [InkStroke] = []
    var fresh: [PKStroke] = []
    for s in strokes {
      var c = s
      c.id = newId()
      c.inputs.points = s.inputs.points.map { var p = $0; p.x += Float(offset.x); p.y += Float(offset.y); return p }
      let pk = c.pkStroke(mask: mask(for: c))
      pending[StrokeKey(pk)] = c
      copies.append(c)
      fresh.append(pk)
    }
    record(before)
    if !fresh.isEmpty { canvas.drawing = PKDrawing(strokes: before.strokes + fresh) }
    var shapeCopies: [ShapeRow] = []
    var z = max(stored.map(\.stroke.z).max() ?? 0, shapeZ)
    for sh in newShapes {
      var c = moved(sh, by: .translate(Float(offset.x), Float(offset.y)))
      c.id = newId()
      z += 1
      c.z = z
      shapeCopies.append(c)
    }
    if !shapeCopies.isEmpty {
      shapeZ = z
      setShapes(shapes + shapeCopies)
    }
    reportUndo()
    return (copies, shapeCopies)
  }

  private func select(_ strokes: [InkStroke], shapes picked: [ShapeRow] = []) {
    lasso.picked = Set(strokes.map(\.id))
    lasso.pickedShapes = Set(picked.map(\.id))
    lasso.bounds = joined(unionOf(strokes), unionOf(picked))
    redrawSelection()
  }

  /// The bounds of [strokes] together.
  private func unionOf(_ strokes: [InkStroke]) -> CGRect? {
    var out: CGRect?
    for s in strokes {
      let r = CGRect(s.bounds)
      out = out.map { $0.union(r) } ?? r
    }
    return out
  }

  // MARK: Hold to paste

  @objc func pasteHold(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began, let canvas, !InkClipboard.isEmpty else { return }
    let p = world(g)
    lasso.pasteAt = p
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let z = canvas.zoomScale
    parent.onPasteOffer(canvas.convert(CGPoint(x: p.x * z, y: p.y * z), to: nil))
  }

  /// Pastes what's copied centred on where the hold was, and picks it up.
  func pasteAtOffer() {
    parent.onPasteOffer(nil)
    guard let at = lasso.pasteAt else { return }
    lasso.pasteAt = nil
    let strokes = InkClipboard.strokes, clipShapes = InkClipboard.shapes
    guard let b = joined(unionOf(strokes), unionOf(clipShapes)) else { return }
    let copies = add(strokes, shapes: clipShapes, offset: CGPoint(x: at.x - b.midX, y: at.y - b.midY))
    if parent.tool == .lasso { select(copies.strokes, shapes: copies.shapes) }
  }
}

// MARK: The menu's ⋯ part: colour, thickness, order, mirror

extension NoteCanvas.Coordinator {
  /// Replaces what's picked up with [change] applied to each stroke (same ids), as one undo step.
  private func restyle(_ change: (inout InkStroke) -> Void, shapes shapeChange: (inout ShapeRow) -> Void = { _ in }) {
    guard let canvas, lasso.bounds != nil else { return }
    let before = canvas.drawing
    var strokes: [PKStroke] = []
    var changedAll: [InkStroke] = []
    for (i, pk) in before.strokes.enumerated() {
      guard i < stored.count, lasso.picked.contains(stored[i].stroke.id) else {
        strokes.append(pk)
        continue
      }
      var s = stored[i].stroke
      change(&s)
      let fresh = s.pkStroke(mask: mask(for: s))
      pending[StrokeKey(fresh)] = s
      strokes.append(fresh)
      changedAll.append(s)
    }
    record(before)
    if !changedAll.isEmpty { canvas.drawing = PKDrawing(strokes: strokes) }
    var changedShapes: [ShapeRow] = []
    var next: [ShapeRow] = []
    for sh in shapes {
      var c = sh
      if lasso.pickedShapes.contains(sh.id) {
        shapeChange(&c)
        changedShapes.append(c)
      }
      next.append(c)
    }
    setShapes(next)
    reportUndo()
    lasso.bounds = joined(unionOf(changedAll), unionOf(changedShapes))
    redrawSelection()
  }

  func recolourSelection(_ argb: UInt32) {
    restyle({ s in
      let c = argb | 0xFF00_0000
      s.color = Int32(bitPattern: s.pen == .HIGHLIGHTER ? (c & 0x00FF_FFFF) | (PenSlot.highlighterAlpha << 24) : c)
    }, shapes: { sh in
      // A shape keeps its own opacity (Android: recolouring keeps it).
      sh.color = Int32(bitPattern: (UInt32(bitPattern: sh.color) & 0xFF00_0000) | (argb & 0x00FF_FFFF))
    })
  }

  func thickenSelection(_ size: Float) {
    restyle({ s in s.size = size }, shapes: { sh in sh.size = size })
  }

  /// Mirrors what's picked up around its own middle (writing flips, as on Android).
  func mirrorSelection(horizontal: Bool) {
    guard let b = lasso.bounds else { return }
    let cx = Float(b.midX), cy = Float(b.midY)
    let flip = Affine.scaleAround(Pt(cx, cy), horizontal ? -1 : 1, horizontal ? 1 : -1)
    let mirror: (ShapeRow, Affine) -> ShapeRow = { self.moved($0, by: $1) }
    restyle({ s in
      s.inputs.points = s.inputs.points.map { p in
        var q = p
        if horizontal { q.x = 2 * cx - p.x } else { q.y = 2 * cy - p.y }
        return q
      }
    }, shapes: { sh in sh = mirror(sh, flip) })
  }

  /// Brings what's picked up in front of everything else, or sends it behind (Android's Arrange).
  func arrangeSelection(toFront: Bool) {
    guard let canvas, !lasso.picked.isEmpty else { return }
    let before = canvas.drawing
    let indices = before.strokes.indices
    let mine = indices.filter { $0 < stored.count && lasso.picked.contains(stored[$0].stroke.id) }
    let others = indices.filter { !mine.contains($0) }
    let order = toFront ? others + mine : mine + others
    // New stacking numbers in the new order, saved straight away (the strokes themselves don't change).
    let zs = stored.map(\.stroke.z)
    let lo = zs.min() ?? 0
    var newStored = order.compactMap { $0 < stored.count ? stored[$0] : nil }
    for k in newStored.indices {
      newStored[k].stroke.z = lo + Int64(k)
      try? parent.db.put(newStored[k].stroke.row, in: parent.notebook.id)
    }
    stored = newStored
    record(before)
    loading = true
    canvas.drawing = PKDrawing(strokes: order.map { before.strokes[$0] })
    loading = false
    reportUndo()
    redrawSelection()
  }
}
