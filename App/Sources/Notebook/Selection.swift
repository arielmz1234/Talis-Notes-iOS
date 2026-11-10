import PencilKit
import TaliCore
import UIKit

/// What the lasso is doing and what it has picked up.
struct LassoState {
  var pan: UIPanGestureRecognizer?
  var hold: UILongPressGestureRecognizer?
  /// The loop being drawn, in world units.
  var loop: [Pt] = []
  /// The ids of the strokes picked up, and their bounds (world units).
  var picked: Set<String> = []
  var bounds: CGRect?
  /// Moving what's picked up: where the drag began and the drawing before it.
  var moving = false
  var moveStart: CGPoint = .zero
  var before: PKDrawing?
  /// Where a hold offered Paste (world units).
  var pasteAt: CGPoint?
  let loopLayer = CAShapeLayer()
  let frameLayer = CAShapeLayer()
}

/// Strokes copied or cut, carried across notebooks (Android's `Clipboard`), in world units.
@MainActor
enum InkClipboard {
  static var strokes: [InkStroke] = []
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
    let pan = UIPanGestureRecognizer(target: self, action: #selector(lassoPan(_:)))
    pan.maximumNumberOfTouches = 1
    pan.delegate = self
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
  }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    // The hold runs alongside everything; the lasso alongside PencilKit's own recognisers (scrolling
    // waits for it to fail instead).
    if g === lasso.hold { return true }
    if g === lasso.pan { return other !== canvas?.panGestureRecognizer }
    return false
  }

  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    if g === lasso.hold { return !InkClipboard.strokes.isEmpty && !parent.viewOnly }
    return true
  }

  private var accent: UIColor { UIColor(argb: Int32(bitPattern: 0xFF7A_4ED6)) }

  private func world(_ g: UIGestureRecognizer) -> CGPoint {
    guard let canvas else { return .zero }
    let p = g.location(in: canvas)  // content coordinates (the scroll view's bounds origin is its offset)
    return CGPoint(x: p.x / canvas.zoomScale, y: p.y / canvas.zoomScale)
  }

  // MARK: Drawing the loop and moving

  @objc func lassoPan(_ g: UIPanGestureRecognizer) {
    guard let canvas else { return }
    let p = world(g)
    switch g.state {
    case .began:
      let pad = 8 / canvas.zoomScale
      if let b = lasso.bounds, b.insetBy(dx: -pad, dy: -pad).contains(p) {
        lasso.moving = true
        lasso.moveStart = p
        lasso.before = canvas.drawing
        parent.onSelection(nil)
      } else {
        clearSelection()
        lasso.loop = [Pt(Float(p.x), Float(p.y))]
      }
    case .changed:
      if lasso.moving, let before = lasso.before {
        let t = CGAffineTransform(translationX: p.x - lasso.moveStart.x, y: p.y - lasso.moveStart.y)
        loading = true
        canvas.drawing = PKDrawing(strokes: before.strokes.enumerated().map { i, s in
          guard i < stored.count, lasso.picked.contains(stored[i].stroke.id) else { return s }
          var m = s
          m.transform = s.transform.concatenating(t)
          return m
        })
        loading = false
        if let b = lasso.bounds { drawFrame(b.applying(t)) }
      } else {
        lasso.loop.append(Pt(Float(p.x), Float(p.y)))
        drawLoop()
      }
    case .ended, .cancelled, .failed:
      if lasso.moving {
        lasso.moving = false
        let dx = p.x - lasso.moveStart.x, dy = p.y - lasso.moveStart.y
        if let before = lasso.before, abs(dx) + abs(dy) > 0.5 {
          let moved = canvas.drawing
          record(before)
          sync(moved)
          lasso.bounds = lasso.bounds?.offsetBy(dx: dx, dy: dy)
          reportUndo()
        }
        lasso.before = nil
        redrawSelection()
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
    lasso.picked = picked
    lasso.bounds = picked.isEmpty ? nil : bounds
    if ProcessInfo.processInfo.arguments.contains("-uitest") { parent.onHint("lasso \(loop.count) points, \(picked.count) picked") }
    if !picked.isEmpty { UISelectionFeedbackGenerator().selectionChanged() }
    redrawSelection()
  }

  func clearSelection() {
    lasso.picked = []
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
  private func record(_ before: PKDrawing) {
    canvas?.undoManager?.registerUndo(withTarget: self) { coord in
      MainActor.assumeIsolated {
        guard let canvas = coord.canvas else { return }
        let now = canvas.drawing
        coord.clearSelection()
        coord.record(now)
        canvas.drawing = before
        coord.reportUndo()
      }
    }
  }

  func copySelection() {
    InkClipboard.strokes = pickedStrokes
    parent.onHint(L("copied_hold_anywhere_to_paste_it"))
  }

  func cutSelection() {
    InkClipboard.strokes = pickedStrokes
    deleteSelection()
    parent.onHint(L("cut_hold_anywhere_to_paste_it_2"))
  }

  func deleteSelection() {
    guard let canvas, !lasso.picked.isEmpty else { return }
    let before = canvas.drawing
    let keep = before.strokes.enumerated().filter { i, _ in i >= stored.count || !lasso.picked.contains(stored[i].stroke.id) }.map(\.element)
    clearSelection()
    record(before)
    canvas.drawing = PKDrawing(strokes: keep)
    reportUndo()
  }

  /// Copies a little down and to the right, and picks the copies up instead (Android: 24 units).
  func duplicateSelection() {
    let copies = add(pickedStrokes, offset: CGPoint(x: Self.duplicateOffset, y: Self.duplicateOffset))
    select(copies)
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
    let added = add([box], offset: .zero)
    select(pickedStrokes + added)
  }

  /// Adds copies of [strokes] moved by [offset] with new ids, as one undo step; returns them.
  @discardableResult
  private func add(_ strokes: [InkStroke], offset: CGPoint) -> [InkStroke] {
    guard let canvas, !strokes.isEmpty else { return [] }
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
    canvas.drawing = PKDrawing(strokes: before.strokes + fresh)
    reportUndo()
    return copies
  }

  private func select(_ strokes: [InkStroke]) {
    lasso.picked = Set(strokes.map(\.id))
    lasso.bounds = unionOf(strokes)
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
    guard g.state == .began, let canvas, !InkClipboard.strokes.isEmpty else { return }
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
    let strokes = InkClipboard.strokes
    guard let b = unionOf(strokes) else { return }
    let copies = add(strokes, offset: CGPoint(x: at.x - b.midX, y: at.y - b.midY))
    if parent.tool == .lasso { select(copies) }
  }
}

// MARK: The menu's ⋯ part: colour, thickness, order, mirror

extension NoteCanvas.Coordinator {
  /// Replaces what's picked up with [change] applied to each stroke (same ids), as one undo step.
  private func restyle(_ change: (inout InkStroke) -> Void) {
    guard let canvas, !lasso.picked.isEmpty else { return }
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
    canvas.drawing = PKDrawing(strokes: strokes)
    reportUndo()
    lasso.bounds = changedAll.reduce(nil as CGRect?) { acc, s in
      let r = CGRect(s.bounds)
      return acc.map { $0.union(r) } ?? r
    }
    redrawSelection()
  }

  func recolourSelection(_ argb: UInt32) {
    restyle { s in
      let c = argb | 0xFF00_0000
      s.color = Int32(bitPattern: s.pen == .HIGHLIGHTER ? (c & 0x00FF_FFFF) | (PenSlot.highlighterAlpha << 24) : c)
    }
  }

  func thickenSelection(_ size: Float) {
    restyle { s in s.size = size }
  }

  /// Mirrors what's picked up around its own middle (writing flips, as on Android).
  func mirrorSelection(horizontal: Bool) {
    guard let b = lasso.bounds else { return }
    let cx = Float(b.midX), cy = Float(b.midY)
    restyle { s in
      s.inputs.points = s.inputs.points.map { p in
        var q = p
        if horizontal { q.x = 2 * cx - p.x } else { q.y = 2 * cy - p.y }
        return q
      }
    }
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
