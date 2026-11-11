import PencilKit
import TaliCore
import UIKit

/// A picked-up shape's dots (Android's `drawShapeHandles`, `handleAt` and `Mode.HANDLE_DRAG`): when
/// the lasso has picked up one shape and nothing else, its dots show; dragging one reshapes it live
/// (`ShapeGeometry.withHandle`), and letting go keeps it, one undo step, still picked up.
/// Not ported yet: snapping a dot onto other shapes and lining it up with them.
extension NoteCanvas.Coordinator {
  /// Android's dot sizes, in points on screen.
  private static let tinyShape: CGFloat = 32
  private static let minHit: CGFloat = 9
  private static let maxHit: CGFloat = 24

  /// The one shape picked up on its own, whose dots show.
  var activeShape: ShapeRow? {
    guard lasso.picked.isEmpty, lasso.pickedTexts.isEmpty, lasso.pickedShapes.count == 1 else { return nil }
    if let live = lasso.handleLive { return live }
    return shapes.first { lasso.pickedShapes.contains($0.id) }
  }

  func installShapeDots(on v: PKCanvasView) {
    let l = lasso.dotsLayer
    l.fillColor = UIColor.white.cgColor
    l.strokeColor = UIColor(argb: Int32(bitPattern: 0xFF4F_7BE8)).cgColor
    l.lineWidth = 2
    l.zPosition = 11
    v.layer.addSublayer(l)
  }

  /// How big [s] is on screen, for sizing its dots: a line's, arc's or curve's length, else its shorter side.
  private func screenSize(_ s: ShapeRow) -> CGFloat {
    guard let canvas, let b = s.geometry.bounds(s.size) else { return 0 }
    let z = canvas.zoomScale
    let w = CGFloat(b.width) * z, h = CGFloat(b.height) * z
    switch s.geometry {
    case .line, .arc, .curve: return max(w, h)
    default: return min(w, h)
    }
  }

  private func content(_ p: Pt) -> CGPoint {
    let z = canvas?.zoomScale ?? 1
    return CGPoint(x: CGFloat(p.x) * z, y: CGFloat(p.y) * z)
  }

  func drawShapeDots() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    guard let s = activeShape, !lasso.moving else {
      lasso.dotsLayer.path = nil
      return
    }
    let size = screenSize(s)
    // Smaller dots on a small shape; none on a tiny one (it's moved and resized whole).
    if size < Self.tinyShape && lasso.handle == nil {
      lasso.dotsLayer.path = nil
      return
    }
    let r = min(max(size * 0.12, 4.5), 6.5)
    let path = CGMutablePath()
    for h in s.geometry.handles() {
      let c = content(h)
      path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
    lasso.dotsLayer.path = path
  }

  /// The dot of [s] under [p] (world units), or nil. On a small shape the dots reach less far, and a
  /// touch nearer the shape's middle than the nearest dot moves the shape instead.
  private func dotAt(_ s: ShapeRow, _ p: CGPoint) -> Int? {
    let handles = s.geometry.handles()
    let size = screenSize(s)
    guard !handles.isEmpty, size >= Self.tinyShape, let b = s.geometry.bounds(s.size) else { return nil }
    let q = content(Pt(Float(p.x), Float(p.y)))
    let dists = handles.map { h -> CGFloat in
      let c = content(h)
      return hypot(c.x - q.x, c.y - q.y)
    }
    guard let i = dists.indices.min(by: { dists[$0] < dists[$1] }) else { return nil }
    let reach = min(max(size * 0.3, Self.minHit), Self.maxHit)
    if dists[i] >= reach { return nil }
    let z = canvas?.zoomScale ?? 1
    let area = CGRect(x: CGFloat(b.left) * z, y: CGFloat(b.top) * z, width: CGFloat(b.width) * z, height: CGFloat(b.height) * z).insetBy(dx: -8, dy: -8)
    let mid = content(b.center)
    if area.contains(q) && hypot(mid.x - q.x, mid.y - q.y) < dists[i] { return nil }
    return i
  }

  /// A touch landing at [p] (world units) on a dot of the shape picked up starts dragging it.
  func beginDotDrag(at p: CGPoint) -> Bool {
    guard !parent.viewOnly, let s = activeShape, let i = dotAt(s, p) else { return false }
    let h = s.geometry.handles()[i]
    lasso.handle = i
    lasso.handleBase = s
    lasso.handleLive = s
    // Keep where on the dot she grabbed it, so the shape doesn't jump to the pen tip.
    lasso.handleGrab = Pt(h.x - Float(p.x), h.y - Float(p.y))
    liftShapes()
    parent.onSelection(nil)
    return true
  }

  func dragDot(to p: CGPoint) {
    guard let i = lasso.handle, let base = lasso.handleBase else { return }
    let raw = Pt(Float(p.x) + lasso.handleGrab.x, Float(p.y) + lasso.handleGrab.y)
    let bg = base.geometry
    var g: ShapeGeometry
    switch bg {
    case let .load(a, b, _, _) where i < 2:
      // A load's end keeps to the same tidy angles as a line's.
      let fixed = i == 0 ? b : a
      g = bg.withHandle(i, Self.tidyEnd(fixed, raw))
    default:
      g = bg.withHandle(i, raw)
    }
    // A line's end snaps to the same tidy angles as a freshly drawn line.
    if case let .line(a, b, s, e, t) = g {
      g = i == 1 ? .line(a: a, b: Self.tidyEnd(a, b), arrowStart: s, arrowEnd: e, ticks: t)
        : .line(a: Self.tidyEnd(b, a), b: b, arrowStart: s, arrowEnd: e, ticks: t)
    }
    var live = base
    live.geometry = g
    lasso.handleLive = live
    guard let canvas else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lasso.shapeLayer.sublayers = [shapeLayer(for: live, zoom: canvas.zoomScale)]
    CATransaction.commit()
    if let b = g.bounds(live.size) { lasso.bounds = CGRect(b) }
    redrawSelection()
  }

  /// Where [end] goes from [fixed] on a tidy angle (every 45°), as `ShapeRecognizer.snappedLine`.
  private static func tidyEnd(_ fixed: Pt, _ end: Pt) -> Pt {
    if case let .line(_, b, _, _, _) = ShapeRecognizer.snappedLine(fixed, end) { return b }
    return end
  }

  func endDotDrag() {
    guard lasso.handle != nil, let base = lasso.handleBase else { return }
    let live = lasso.handleLive ?? base
    let before = lasso.shapesBefore ?? shapes
    lasso.handle = nil
    lasso.handleBase = nil
    lasso.handleLive = nil
    if live.geometry != base.geometry, let canvas {
      record(canvas.drawing, shapes: before)
      setShapes(before.map { $0.id == live.id ? live : $0 })
      reportUndo()
    } else {
      setShapes(before)
      // A dot tapped without moving changes nothing (and makes no undo step).
    }
    dropShapes()
    if let b = live.geometry.bounds(live.size) { lasso.bounds = CGRect(b) }
    redrawSelection()
  }

  /// A picked-up shape drawn in the overlay the way the page draws it.
  func shapeLayer(for s: ShapeRow, zoom z: CGFloat) -> CAShapeLayer {
    let l = CAShapeLayer()
    let path = CGMutablePath()
    for line in s.geometry.paths(s.size) where line.count > 1 {
      path.addLines(between: line.map { CGPoint(x: CGFloat($0.x) * z, y: CGFloat($0.y) * z) })
    }
    l.path = path
    l.strokeColor = UIColor(argb: s.color).cgColor
    l.lineWidth = CGFloat(s.size) * z
    l.lineCap = .round
    l.lineJoin = .round
    if let fill = s.fill, s.geometry.closed { l.fillColor = UIColor(argb: fill).cgColor } else { l.fillColor = UIColor.clear.cgColor }
    if let dash = LineDash.pattern(s.line, width: CGFloat(s.size) * z) { l.lineDashPattern = dash.map { NSNumber(value: Double($0)) } }
    return l
  }
}
