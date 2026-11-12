import PencilKit
import TaliCore
import UIKit

/// The Shapes tool (Android's `Tool.SHAPE`, `buildShape`): the pen (or a finger where fingers draw)
/// drags out the chosen shape, shown live, kept on lift. A tap draws nothing: only a slide of
/// `startSlide` (Android's `SHAPE_START_DP`). Shapes take the look of the pen last used.
struct ShapeToolState {
  var watcher: StrokeWatcher?
  var start: Pt?
  var startScreen: CGPoint = .zero
  var drawing = false
  var preview: ShapeRow?
  /// The start locked onto another shape, or lined up with them (its guides).
  var startStuck = false
  var startGuides: [SnapGuide] = []
  /// The touch went to the shape just drawn (still picked up): its dots, chips, rotate handle or
  /// inside it, which edit or move it as the lasso's selection does.
  var editing = false
  let layer = CAShapeLayer()
}

extension NoteCanvas.Coordinator {
  static let shapeStartSlide: CGFloat = 12

  func installShapeTool(on v: PKCanvasView) {
    let w = StrokeWatcher(target: nil, action: nil)
    w.delegate = self
    w.isEnabled = false
    w.accepts = { [weak self] t in self?.drawsShapes(t) ?? false }
    w.began = { [weak self] t, _ in self?.shapeBegan(t) }
    w.moved = { [weak self] t, e in
      guard let self else { return }
      if self.shapeTool.editing {
        for s in e.coalescedTouches(for: t) ?? [t] { self.lassoStep(.changed, s) }
      } else {
        self.shapeMoved(t)
      }
    }
    w.ended = { [weak self] cancelled in
      guard let self else { return }
      if self.shapeTool.editing {
        self.shapeTool.editing = false
        self.lassoStep(cancelled ? .cancelled : .ended, nil)
      } else {
        self.shapeEnded(cancelled)
      }
    }
    v.addGestureRecognizer(w)
    // One finger or the pen draws the shape; scrolling waits until it's clear it isn't one.
    v.panGestureRecognizer.require(toFail: w)
    shapeTool.watcher = w
    shapeTool.layer.fillColor = UIColor.clear.cgColor
    shapeTool.layer.lineCap = .round
    shapeTool.layer.lineJoin = .round
    shapeTool.layer.zPosition = 9
    v.layer.addSublayer(shapeTool.layer)
  }

  /// The pen draws shapes; a finger only where fingers draw.
  private func drawsShapes(_ t: UITouch) -> Bool {
    guard let canvas, parent.tool == .shape, !parent.viewOnly else { return false }
    if t.type == .pencil { return true }
    switch canvas.drawingPolicy {
    case .anyInput: return true
    case .pencilOnly: return false
    default: return !UIPencilInteraction.prefersPencilOnlyDrawing
    }
  }

  /// The look shapes are drawn with: the pen last used (Android's "Like the pen", until a shape style is set).
  var shapePen: PenSlot {
    parent.pens.first { $0.id == lastPenId } ?? parent.pens.first ?? PenSlot.defaults[0]
  }

  private func shapeBegan(_ t: UITouch) {
    guard let canvas else { return }
    // The shape just drawn is still picked up: dragging inside it moves it rather than starting
    // another (Android: the pen with the Shapes tool doesn't write through), its dots reshape it,
    // its chips and handle resize, move and turn it. Anywhere else starts a new shape.
    if lasso.bounds != nil {
      let q = t.location(in: canvas)
      let z = canvas.zoomScale
      let p = CGPoint(x: q.x / z, y: q.y / z)
      lasso.lastAt = p
      if beginDotDrag(at: p) || beginResize(at: p) || beginRotate(at: p) {
        shapeTool.editing = true
        return
      }
      if let b = lasso.bounds, b.insetBy(dx: -8 / z, dy: -8 / z).contains(p) || onMoveChip(p) {
        shapeTool.editing = true
        lassoStep(.began, t)
        return
      }
    }
    clearSelection()
    let q = t.location(in: canvas)
    shapeTool.startScreen = q
    let p = Pt(Float(q.x / canvas.zoomScale), Float(q.y / canvas.zoomScale))
    // A new shape can start right on another one (a line from a corner or off an edge); not
    // touching anything, it starts lined up with other shapes' sides, middles and corners.
    let z = Float(canvas.zoomScale)
    func session() -> SnapSession { SnapSession(contact: Self.snapPt / z, align: Self.alignPt / z) }
    let targets = snapTargets(skipping: Set<String>())
    lasso.snapTargets = targets
    let stuck = Snap.point(p, targets, session())
    let lined = stuck == nil ? Snap.alignPoint(p, targets, session()) : nil
    lasso.snap = session()
    shapeTool.start = stuck ?? lined?.0 ?? p
    shapeTool.startStuck = stuck != nil
    shapeTool.startGuides = lined?.1 ?? []
    shapeTool.drawing = false
    shapeTool.preview = nil
  }

  private func shapeMoved(_ t: UITouch) {
    guard let canvas, let start = shapeTool.start else { return }
    let q = t.location(in: canvas)
    if !shapeTool.drawing {
      guard hypot(q.x - shapeTool.startScreen.x, q.y - shapeTool.startScreen.y) >= Self.shapeStartSlide else { return }
      shapeTool.drawing = true
    }
    let raw = Pt(Float(q.x / canvas.zoomScale), Float(q.y / canvas.zoomScale))
    let kind = parent.shapeKind
    let z = Float(canvas.zoomScale)
    let snap = lasso.snap ?? SnapSession(contact: Self.snapPt / z)
    lasso.snap = snap
    snap.begin(contact: Self.snapPt / z, align: Self.alignPt / z)
    let targets = lasso.snapTargets
    // Where the drag ends: a line's end onto an edge or corner; a box's corner onto a corner or
    // edge, or lined up with other shapes. Shapes drawn out from a point only snap where they start.
    let result: (Pt, [SnapGuide])
    if kind.drawnFromPoint {
      result = (raw, [])
    } else if kind.drawnAsLine {
      let (p, on) = lineEndAt(start, raw, targets, snap)
      if on {
        result = (p, [.touch(p)])
      } else if p.dist(raw) > 0.01 {
        // On a tidy angle already: it keeps it, sliding along to line up with other shapes.
        let r = Snap.alongAngle(start, p, targets, snap)
        result = r.1.isEmpty ? (raw, []) : r
      } else {
        result = Snap.alignPoint(raw, targets, snap)
      }
    } else if let p = Snap.point(raw, targets, snap) {
      result = (p, [.touch(p)])
    } else {
      result = Snap.alignPoint(raw, targets, snap)
    }
    let (end, guides) = result
    showSnap((shapeTool.startStuck ? [SnapGuide.touch(start)] : []) + shapeTool.startGuides + guides)
    // The Shapes tool has its own style (its panel's Style tab), apart from the pen in use.
    let look = ShapeLook.look(parent.pens.first { $0.id == lastPenId }, parent.pens)
    let geometry = kind.drawn(start, end, keepEnd: !guides.isEmpty)
    shapeTool.preview = ShapeRow(
      geometry: geometry, pen: "FINELINER", color: look.outlineArgb, size: look.size,
      fill: geometry.closed ? look.fillArgb : nil, line: look.line)
    drawShapePreview()
  }

  private func shapeEnded(_ cancelled: Bool) {
    let shape = shapeTool.drawing && !cancelled ? shapeTool.preview : nil
    shapeTool.start = nil
    shapeTool.drawing = false
    shapeTool.preview = nil
    shapeTool.startStuck = false
    shapeTool.startGuides = []
    lasso.snap = nil
    showSnap([])
    drawShapePreview()
    // A shape stays picked up after it's drawn, ready to adjust (Android's soft selection).
    if let shape { select([], shapes: [addShape(shape)]) }
  }

  private func drawShapePreview() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    guard let canvas, let s = shapeTool.preview else {
      shapeTool.layer.path = nil
      return
    }
    let z = canvas.zoomScale
    let path = CGMutablePath()
    for line in s.geometry.paths(s.size) where line.count > 1 {
      path.addLines(between: line.map { CGPoint(x: CGFloat($0.x) * z, y: CGFloat($0.y) * z) })
    }
    shapeTool.layer.path = path
    shapeTool.layer.strokeColor = UIColor(argb: s.color).cgColor
    shapeTool.layer.lineWidth = CGFloat(s.size) * z
    // Its fill under the outline, and its line style, as it will be on the page.
    shapeTool.layer.fillColor = s.fill.map { UIColor(argb: $0).cgColor } ?? UIColor.clear.cgColor
    shapeTool.layer.lineDashPattern = LineDash.pattern(s.line, width: CGFloat(s.size) * z)?.map { NSNumber(value: Double($0)) }
  }
}
