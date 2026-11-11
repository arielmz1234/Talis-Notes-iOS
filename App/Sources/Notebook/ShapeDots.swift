import PencilKit
import TaliCore
import UIKit

/// A picked-up shape's dots (Android's `drawShapeHandles`, `handleAt` and `Mode.HANDLE_DRAG`): when
/// the lasso has picked up one shape and nothing else, its dots show; dragging one reshapes it live
/// (`ShapeGeometry.withHandle`), and letting go keeps it, one undo step, still picked up.
/// A dot snaps onto other shapes on screen and lines up with them (`TaliCore/Snap.swift`).
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
    installSnapGuides(on: v)
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
    let z = Float(canvas?.zoomScale ?? 1)
    let snap = lasso.snap ?? SnapSession(contact: Self.snapPt / z, align: Self.alignPt / z)
    lasso.snap = snap
    snap.begin(contact: Self.snapPt / z, align: Self.alignPt / z)
    let targets = snapTargets(skipping: base.id)
    // A line's or a distributed load's end: the other end, which it turns about.
    var lineFixed: Pt?
    switch bg {
    case let .line(a, b, _, _, _): lineFixed = i == 0 ? b : a
    case let .load(a, b, _, _) where i < 2: lineFixed = i == 0 ? b : a
    default: break
    }
    // A dot dragged onto another shape's corner or edge locks on there (a line meeting a line).
    var stuck: Pt?
    if let fixed = lineFixed {
      let (q, on) = lineEndAt(fixed, raw, targets, snap)
      if on { stuck = q }
    } else {
      stuck = Snap.point(raw, targets, snap)
    }
    // Not touching anything: it lines up with other shapes' sides, middles and corners (and its own
    // shape's other corners); a line's end on a tidy angle slides along the line to line up.
    var aligned: (Pt, [SnapGuide])?
    if stuck == nil {
      let tidy = lineFixed.map { Self.tidyEnd($0, raw) }
      if let fixed = lineFixed, let tidy, tidy.dist(raw) > 0.01 {
        let r = Snap.alongAngle(fixed, tidy, targets, snap)
        if !r.1.isEmpty { aligned = r }
      } else {
        let r = Snap.alignPoint(raw, targets + Self.ownCorners(bg, i), snap)
        if !r.1.isEmpty { aligned = r }
      }
    }
    let at = stuck ?? aligned?.0
    var g: ShapeGeometry
    if let at {
      switch bg {
      case let .triangle(a, b, c, turn):
        g = .triangle(a: i == 0 ? at : a, b: i == 1 ? at : b, c: i == 2 ? at : c, turn: turn)
      case let .line(a, b, s, e, t):
        g = .line(a: i == 0 ? at : a, b: i == 0 ? b : at, arrowStart: s, arrowEnd: e, ticks: t)
      default:
        g = bg.withHandle(i, at)
      }
    } else if let fixed = lineFixed, case .load = bg {
      // A load's end not touching anything keeps to the same tidy angles as a line's.
      g = bg.withHandle(i, Self.tidyEnd(fixed, raw))
    } else {
      g = bg.withHandle(i, raw)
    }
    // A line's end snaps to the same tidy angles as a freshly drawn line.
    if at == nil, case let .line(a, b, s, e, t) = g {
      g = i == 1 ? .line(a: a, b: Self.tidyEnd(a, b), arrowStart: s, arrowEnd: e, ticks: t)
        : .line(a: Self.tidyEnd(b, a), b: b, arrowStart: s, arrowEnd: e, ticks: t)
    }
    showSnap(stuck.map { [SnapGuide.touch($0)] } ?? aligned?.1 ?? [])
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

  /// Android's `SNAP_DP` and `ALIGN_DP`: touching catches from 14 pt on screen, lining up from 8.
  static let snapPt: Float = 14
  static let alignPt: Float = 8

  /// What a dot can snap to: the other shapes on screen (Android's `snapItemsInView`).
  func snapTargets(skipping id: String) -> [SnapFeatures] { snapTargets(skipping: [id]) }

  /// Shapes and text boxes on screen now, apart from [ids]. Handwriting isn't snapped to.
  func snapTargets(skipping ids: Set<String>) -> [SnapFeatures] {
    guard let canvas else { return [] }
    let z = canvas.zoomScale
    let b = canvas.bounds
    let view = Rect(Float(b.minX / z), Float(b.minY / z), Float(b.maxX / z), Float(b.maxY / z))
    let shapeTargets: [SnapFeatures] = (lasso.shapesBefore ?? shapes).compactMap { s in
      guard !ids.contains(s.id), let r = s.geometry.bounds(s.size), r.intersects(view) else { return nil }
      return s.geometry.snapFeatures()
    }
    let textTargets: [SnapFeatures] = (lasso.textsBefore ?? texts).compactMap { t in
      guard !ids.contains(t.id) else { return nil }
      let r = Self.rect(TextLook.frame(t))
      return r.intersects(view) ? Self.boxFeatures(r) : nil
    }
    return shapeTargets + textTargets
  }

  static func rect(_ f: CGRect) -> Rect { Rect(Float(f.minX), Float(f.minY), Float(f.maxX), Float(f.maxY)) }

  /// A box's corners, centre and sides (Android's `boxFeatures`, for pictures and text boxes).
  static func boxFeatures(_ r: Rect) -> SnapFeatures {
    let c = [Pt(r.left, r.top), Pt(r.right, r.top), Pt(r.right, r.bottom), Pt(r.left, r.bottom)]
    return SnapFeatures(c + [r.center], c.indices.map { (c[$0], c[($0 + 1) % 4]) }, r)
  }

  /// Starts snapping a move of what's picked up (Android's `startMoveSnap`): shapes and text boxes
  /// snap by their own features; handwriting alone lines up only the middle of its box.
  func startMoveSnap() {
    guard let canvas else { return }
    let z = Float(canvas.zoomScale)
    lasso.snap = SnapSession(contact: Self.snapPt / z, align: Self.alignPt / z)
    var parts = shapes.filter { lasso.pickedShapes.contains($0.id) }.map { $0.geometry.snapFeatures() }
    parts += texts.filter { lasso.pickedTexts.contains($0.id) }.map { Self.boxFeatures(Self.rect(TextLook.frame($0))) }
    if !parts.isEmpty {
      let f = SnapFeatures.of(parts)
      // A big selection just lines up by its box (checking every corner of every part would be slow).
      lasso.snapMoving = f.points.count > 80 || f.segments.count > 600 ? SnapFeatures([], [], f.box) : f
    } else if let b = lasso.bounds {
      lasso.snapMoving = SnapFeatures.middleOf(Self.rect(b))
    } else {
      lasso.snapMoving = nil
    }
    lasso.snapTargets = snapTargets(skipping: lasso.pickedShapes.union(lasso.pickedTexts))
  }

  /// The carry [dx], [dy] (world units) nudged to lock onto nearby shapes, showing the guides.
  func snappedMove(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
    guard let m = lasso.snapMoving, let s = lasso.snap, let canvas else { return CGPoint(x: dx, y: dy) }
    let z = Float(canvas.zoomScale)
    s.begin(contact: Self.snapPt / z, align: Self.alignPt / z)
    let r = Snap.move(m.moved(Float(dx), Float(dy)), lasso.snapTargets, s)
    showSnap(r.guides)
    return CGPoint(x: dx + CGFloat(r.offset.x), y: dy + CGFloat(r.offset.y))
  }

  /// Where a line's end goes, dragged to [raw] with its other end at [fixed]: onto another shape's
  /// end or corner; else, keeping its tidy angle, onto the edge it reaches; else onto the nearest
  /// edge; else free at its tidy angle. The second value says whether it locked on (Android's `lineEndAt`).
  func lineEndAt(_ fixed: Pt, _ raw: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> (Pt, Bool) {
    if let c = Snap.corner(raw, targets, s) { return (c, true) }
    let angled = Self.tidyEnd(fixed, raw)
    if let q = Snap.alongLine(fixed, angled, targets, s) { return (q, true) }
    if let q = Snap.point(raw, targets, s) { return (q, true) }
    return (angled, false)
  }

  /// The shape's other corners, for a dragged corner to line up with (triangles and free polygons only).
  private static func ownCorners(_ g: ShapeGeometry, _ index: Int) -> [SnapFeatures] {
    let corners: [Pt]
    switch g {
    case let .triangle(a, b, c, _): corners = [a, b, c]
    case let .poly(p, _, smooth, _, _) where !smooth && !g.isRect: corners = p
    default: return []
    }
    return [SnapFeatures(corners.enumerated().filter { $0.offset != index }.map(\.element), [], nil)]
  }

  /// Shows [guides] (dashed lines where things line up, one small cross where it touches) and ends
  /// the frame's snapping; a light tick when something first locks on.
  func showSnap(_ guides: [SnapGuide]) {
    let touch = guides.last { $0.isTouch }
    let shown = guides.filter { !$0.isTouch } + (touch.map { [$0] } ?? [])
    if !shown.isEmpty && !lasso.snapShowing { UISelectionFeedbackGenerator().selectionChanged() }
    lasso.snapShowing = !shown.isEmpty
    lasso.snap?.end()
    let z = canvas?.zoomScale ?? 1
    let pad: CGFloat = 14
    let lines = CGMutablePath(), cross = CGMutablePath()
    for g in shown {
      switch g {
      case let .align(vertical, at, from, to):
        if vertical {
          lines.move(to: CGPoint(x: CGFloat(at) * z, y: CGFloat(from) * z - pad))
          lines.addLine(to: CGPoint(x: CGFloat(at) * z, y: CGFloat(to) * z + pad))
        } else {
          lines.move(to: CGPoint(x: CGFloat(from) * z - pad, y: CGFloat(at) * z))
          lines.addLine(to: CGPoint(x: CGFloat(to) * z + pad, y: CGFloat(at) * z))
        }
      case let .touch(q):
        let c = CGPoint(x: CGFloat(q.x) * z, y: CGFloat(q.y) * z), k: CGFloat = 2.6
        cross.move(to: CGPoint(x: c.x - k, y: c.y - k))
        cross.addLine(to: CGPoint(x: c.x + k, y: c.y + k))
        cross.move(to: CGPoint(x: c.x - k, y: c.y + k))
        cross.addLine(to: CGPoint(x: c.x + k, y: c.y - k))
      }
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lasso.guideLayer.path = lines
    lasso.crossHalo.path = cross
    lasso.crossLayer.path = cross
    CATransaction.commit()
  }

  func installSnapGuides(on v: PKCanvasView) {
    let accent = UIColor(argb: Int32(bitPattern: 0xFF7A_4ED6)).cgColor
    lasso.guideLayer.strokeColor = accent
    lasso.guideLayer.lineWidth = 1.2
    lasso.guideLayer.lineDashPattern = [5, 4]
    lasso.crossHalo.strokeColor = UIColor(white: 1, alpha: 0.9).cgColor
    lasso.crossHalo.lineWidth = 3.4
    lasso.crossLayer.strokeColor = accent
    lasso.crossLayer.lineWidth = 1.4
    for (i, l) in [lasso.guideLayer, lasso.crossHalo, lasso.crossLayer].enumerated() {
      l.fillColor = nil
      l.lineCap = .round
      l.zPosition = 12 + CGFloat(i)
      v.layer.addSublayer(l)
    }
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
    lasso.snap = nil
    showSnap([])
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
