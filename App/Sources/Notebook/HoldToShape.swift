import PencilKit
import TaliCore
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Watches the touch that's writing without taking it from PencilKit: it never recognises, so the
/// pen keeps drawing exactly as before; it only reports where the touch goes.
final class StrokeWatcher: UIGestureRecognizer {
  var began: (UITouch, UIEvent) -> Void = { _, _ in }
  var moved: (UITouch, UIEvent) -> Void = { _, _ in }
  var ended: (Bool) -> Void = { _ in }
  /// Whether to follow a touch at all; one it doesn't want fails the watcher at once (so scrolling,
  /// which may wait for it to fail, goes ahead).
  var accepts: (UITouch) -> Bool = { _ in true }
  private weak var tracked: UITouch?

  override init(target: Any?, action: Selector?) {
    super.init(target: target, action: action)
    cancelsTouchesInView = false
    delaysTouchesBegan = false
    delaysTouchesEnded = false
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    if tracked == nil, let t = touches.first, (event.allTouches?.count ?? 1) == 1 {
      guard accepts(t) else {
        state = .failed
        return
      }
      tracked = t
      began(t, event)
    } else if tracked != nil {
      // A second finger: a pinch or scroll, not writing.
      tracked = nil
      ended(true)
      state = .failed
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    if let t = tracked, touches.contains(t) { moved(t, event) }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    if let t = tracked, touches.contains(t) {
      tracked = nil
      ended(false)
      state = .failed
    }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    if tracked != nil {
      tracked = nil
      ended(true)
    }
    state = .failed
  }

  override func reset() {
    tracked = nil
    super.reset()
  }
}

/// Hold-to-shape (Android's `scheduleHold`, `snapToShape`, `updateLiveShape`): the pen stops for a
/// moment at the end of a stroke and the stroke becomes the clean shape it looks like. Still holding,
/// a line's end follows the pen (snapping to every 45°) and any other shape grows or shrinks around
/// its middle; lifting keeps it.
struct HoldState {
  var watcher: StrokeWatcher?
  /// The stroke so far, in world units, and where the pen last rested.
  var points: [Pt] = []
  var anchor: CGPoint = .zero
  var timer: Timer?
  /// The shape while the pen is still down, the one it snapped to, and where the pen was then.
  var live: ShapeRow?
  var base: ShapeRow?
  var liveAnchor: Pt = .zero
  var following = false
  var screenLength: CGFloat = 0
  var last: CGPoint = .zero
  /// PencilKit strokes begun after this are the one that became a shape: dropped if they arrive.
  var dropSince: Date?
  var began = Date()
  let layer = CAShapeLayer()
}

extension NoteCanvas.Coordinator {
  /// How long the pen rests before the stroke becomes a shape (Android's `holdDelayMs`).
  static let holdDelay: TimeInterval = 0.45
  /// Moving less than this (screen points) still counts as resting (`HOLD_TOLERANCE_DP`).
  static let holdTolerance: CGFloat = 7
  /// A stroke shorter than this on screen stays ink.
  static let holdMinLength: CGFloat = 24

  func installHoldToShape(on v: PKCanvasView) {
    let w = StrokeWatcher(target: nil, action: nil)
    w.delegate = self
    w.began = { [weak self] t, _ in self?.holdBegan(t) }
    w.moved = { [weak self] t, e in self?.holdMoved(t, e) }
    w.ended = { [weak self] cancelled in self?.holdEnded(cancelled) }
    v.addGestureRecognizer(w)
    hold.watcher = w
    hold.layer.fillColor = UIColor.clear.cgColor
    hold.layer.lineCap = .round
    hold.layer.lineJoin = .round
    hold.layer.zPosition = 9
    v.layer.addSublayer(hold.layer)
  }

  /// Whether this touch writes with the pen (not the eraser or lasso, not a finger that only
  /// scrolls, not a touch that took hold of the selection).
  private func writes(_ t: UITouch) -> Bool {
    guard case .pen = parent.tool else { return false }
    return draws(t) && claim(t) == nil
  }

  private func worldPoint(_ t: UITouch) -> CGPoint {
    guard let canvas else { return .zero }
    let p = t.location(in: canvas)
    return CGPoint(x: p.x / canvas.zoomScale, y: p.y / canvas.zoomScale)
  }

  private func holdBegan(_ t: UITouch) {
    stopHoldTimer()
    hold.points = []
    hold.live = nil
    hold.base = nil
    hold.dropSince = nil
    hold.screenLength = 0
    guard writes(t) else { return }
    let p = worldPoint(t)
    hold.began = Date()
    hold.points = [Pt(Float(p.x), Float(p.y))]
    hold.anchor = t.location(in: canvas)
    hold.last = hold.anchor
    scheduleHold()
  }

  private func holdMoved(_ t: UITouch, _ e: UIEvent) {
    guard let canvas, !hold.points.isEmpty || hold.live != nil else { return }
    let samples = e.coalescedTouches(for: t) ?? [t]
    if hold.live != nil {
      followLive(worldPoint(samples.last ?? t))
      return
    }
    for s in samples {
      let sp = s.location(in: canvas)
      hold.screenLength += hypot(sp.x - hold.last.x, sp.y - hold.last.y)
      hold.last = sp
      let p = CGPoint(x: sp.x / canvas.zoomScale, y: sp.y / canvas.zoomScale)
      hold.points.append(Pt(Float(p.x), Float(p.y)))
      if hypot(sp.x - hold.anchor.x, sp.y - hold.anchor.y) > Self.holdTolerance {
        hold.anchor = sp
        scheduleHold()
      }
    }
  }

  private func holdEnded(_ cancelled: Bool) {
    stopHoldTimer()
    if let shape = hold.live {
      hold.live = nil
      hold.base = nil
      hold.layer.path = nil
      if !cancelled { selectShape(addShape(shape), soft: true) }
    } else if !cancelled, let tapped = shapeTappedByPen() {
      dropInk(since: hold.began.addingTimeInterval(-0.2))
      selectShape(tapped)
    }
    hold.points = []
  }

  private func shapeTappedByPen() -> ShapeRow? {
    guard let first = hold.points.first, Date().timeIntervalSince(hold.began) < Self.penTap else { return nil }
    if hold.points.contains(where: { $0.dist(first) * zoom > 4 }) { return nil }
    guard case let .shape(s)? = item(at: first, since: hold.began.addingTimeInterval(-0.2)) else { return nil }
    return s
  }

  /// Takes back the ink PencilKit drew since [since] (the dot of a tap): it lets go of a stroke still
  /// in hand, and one already handed in is taken out again, without an undo step of its own.
  private func dropInk(since: Date) {
    guard let canvas else { return }
    hold.dropSince = since
    canvas.drawingGestureRecognizer.isEnabled = false
    canvas.drawingGestureRecognizer.isEnabled = inkOn
    let kept = canvas.drawing.strokes.filter { $0.path.creationDate < since }
    if kept.count == canvas.drawing.strokes.count { return }
    loading = true
    canvas.undoManager?.disableUndoRegistration()
    canvas.drawing = PKDrawing(strokes: kept)
    canvas.undoManager?.enableUndoRegistration()
    loading = false
    sync(canvas.drawing)
  }

  private func scheduleHold() {
    stopHoldTimer()
    hold.timer = Timer.scheduledTimer(withTimeInterval: Self.holdDelay, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.snapToShape() }
    }
  }

  private func stopHoldTimer() {
    hold.timer?.invalidate()
    hold.timer = nil
  }

  /// The pen rested mid-stroke: turn the stroke into a clean shape, if it clearly is one.
  private func snapToShape() {
    // Her own shapes and the shapes of the subjects she starred are matched too (not every subject's).
    guard let canvas, ShapeSettings.holdToShape, hold.live == nil, hold.points.count > 1, hold.screenLength >= Self.holdMinLength,
      let geometry = ShapeRecognizer.recognize(hold.points, custom: ShapeSettings.customShapes, packs: ShapeSettings.starredShapes)
    else { return }
    let pen = currentPen
    let shape = ShapeRow(geometry: geometry, pen: pen.type.rawValue, color: pen.color, size: pen.size)
    // PencilKit lets go of the stroke it was drawing (switching its recogniser off and on cancels
    // it); should it hand the stroke in anyway, `sync` drops it.
    hold.dropSince = hold.began.addingTimeInterval(-0.2)
    canvas.drawingGestureRecognizer.isEnabled = false
    canvas.drawingGestureRecognizer.isEnabled = true
    hold.live = shape
    hold.base = shape
    hold.liveAnchor = hold.points.last ?? .zero
    hold.following = false
    drawLive()
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
  }

  /// Still holding after the snap: a line's end follows the pen; anything else grows or shrinks.
  private func followLive(_ p: CGPoint) {
    guard let canvas, let base = hold.base else { return }
    let pen = Pt(Float(p.x), Float(p.y))
    if case let .line(a, _, _, false, _) = base.geometry {
      hold.live?.geometry = ShapeRecognizer.snappedLine(a, pen)
    } else {
      let z = Float(canvas.zoomScale)
      if !hold.following && pen.dist(hold.liveAnchor) * z < 10 { return }
      hold.following = true
      let c: Pt
      if case let .ellipse(center, _, _, _, _) = base.geometry {
        c = center
      } else {
        c = base.geometry.bounds(0)?.center ?? hold.liveAnchor
      }
      let from = hold.liveAnchor.dist(c)
      if from < 1 { return }
      let k = min(max(pen.dist(c) / from, 0.15), 8)
      hold.live?.geometry = base.geometry.transformed(.scaleAround(c, k))
    }
    drawLive()
  }

  /// The live shape, drawn over the page until the pen lifts.
  private func drawLive() {
    guard let canvas, let shape = hold.live else {
      hold.layer.path = nil
      return
    }
    let z = canvas.zoomScale
    let path = CGMutablePath()
    for line in shape.geometry.paths(shape.size) where line.count > 1 {
      path.addLines(between: line.map { CGPoint(x: CGFloat($0.x) * z, y: CGFloat($0.y) * z) })
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    hold.layer.path = path
    hold.layer.strokeColor = UIColor(argb: shape.color).cgColor
    hold.layer.lineWidth = CGFloat(shape.size) * z
    CATransaction.commit()
  }

  /// Keeps a finished shape: stored as Android stores it, drawn with the page, one undo step.
  @discardableResult
  func addShape(_ shape: ShapeRow) -> ShapeRow {
    var s = shape
    s.id = newId()
    let z = max(stored.map(\.stroke.z).max() ?? 0, shapeZ) + 1
    shapeZ = z
    s.z = z
    putShape(s, z: z)
    registerShapeUndo(s, z: z)
    return s
  }

  /// Undo takes the shape away; redo puts it back (and can be undone again).
  private func registerShapeUndo(_ s: ShapeRow, z: Int64) {
    canvas?.undoManager?.registerUndo(withTarget: self) { c in
      MainActor.assumeIsolated {
        c.clearSelection()
        c.removeShape(s.id)
        c.canvas?.undoManager?.registerUndo(withTarget: c) { c2 in
          MainActor.assumeIsolated {
            c2.putShape(s, z: z)
            c2.registerShapeUndo(s, z: z)
          }
        }
      }
    }
    reportUndo()
  }

  private func putShape(_ shape: ShapeRow, z: Int64) {
    guard let pages else { return }
    var s = shape
    s.z = z
    pages.pages.under.shapes.append(s)
    do { try parent.db.put(s.row(id: s.id, z: z), in: parent.notebook.id) } catch { CrashNote.log("saving a shape: \(error)") }
    if let b = s.geometry.bounds(s.size) {
      let need = layout.needed(b)
      if paged, need > pageCount {
        pageCount = need
        updateContent()
        persistPages()
      }
    }
    touch()
    pages.layer.setNeedsDisplay()
    reportUndo()
  }

  private func removeShape(_ id: String) {
    guard let pages else { return }
    pages.pages.under.shapes.removeAll { $0.id == id }
    do { try parent.db.removeItem(id) } catch { CrashNote.log("removing a shape: \(error)") }
    touch()
    pages.layer.setNeedsDisplay()
    reportUndo()
  }

  /// Whether a new PencilKit stroke is one that isn't kept: the one that just became a shape, the dot
  /// of a tap that picked a shape up, or one begun by a touch that was editing the selection.
  func isSnappedStroke(_ pk: PKStroke) -> Bool {
    [hold.dropSince, lasso.editSince].contains { since in since.map { pk.path.creationDate >= $0 } ?? false }
  }
}
