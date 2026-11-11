import PencilKit
import TaliCore
import UIKit

enum SelectionGrab: Equatable {
  case resize, move, turn
  case dot(Int, of: ShapeRow)
}

enum SelectionDrag {
  case move(from: Pt)
  case scale(from: Pt)
  case turn(from: Pt, pivot: Pt, facing: Float, angle: Float)
  case dot(index: Int, grab: Pt, base: ShapeRow, live: ShapeRow)
}

struct SelectionInfo: Equatable {
  var rect: CGRect
  var rotatable: Bool
}

enum TappedItem {
  case stroke(String)
  case shape(ShapeRow)
  case text(TextRow)
}

extension Pt {
  init(_ p: CGPoint) { self.init(Float(p.x), Float(p.y)) }
}

extension CGPoint {
  init(_ p: Pt) { self.init(x: CGFloat(p.x), y: CGFloat(p.y)) }
}

extension TaliCore.Rect {
  init(_ r: CGRect) { self.init(Float(r.minX), Float(r.minY), Float(r.maxX), Float(r.maxY)) }
}

extension NoteCanvas.Coordinator {
  static let menuBack: TimeInterval = 0.45
  static let penTap: TimeInterval = 0.25
  static let hitRadius: Float = 10

  var zoom: Float { Float(canvas?.zoomScale ?? 1) }

  var selectionCount: Int { lasso.picked.count + lasso.pickedShapes.count + lasso.pickedTexts.count }

  /// Typed text stays upright, so the rotate handle only shows without it.
  var canRotate: Bool { selectionCount > 0 && lasso.pickedTexts.isEmpty }

  var activeShape: ShapeRow? {
    if case let .dot(_, _, _, live)? = lasso.drag { return live }
    guard lasso.picked.isEmpty, lasso.pickedTexts.isEmpty, lasso.pickedShapes.count == 1, let id = lasso.pickedShapes.first else { return nil }
    return (lasso.shapesBefore ?? shapes).first { $0.id == id }
  }

  var fingersDraw: Bool {
    switch canvas?.drawingPolicy {
    case .anyInput?: true
    case .pencilOnly?, nil: false
    default: !UIPencilInteraction.prefersPencilOnlyDrawing
    }
  }

  func draws(_ t: UITouch) -> Bool { !parent.viewOnly && (t.type == .pencil || fingersDraw) }

  // MARK: Where things are

  private func screenFrame(_ b: CGRect, by t: Affine = .identity) -> TaliCore.Rect {
    let z = zoom
    let a = t.apply(Pt(Float(b.minX), Float(b.minY))) * z, c = t.apply(Pt(Float(b.maxX), Float(b.maxY))) * z
    return TaliCore.Rect(min(a.x, c.x), min(a.y, c.y), max(a.x, c.x), max(a.y, c.y)).outset(SelectionHandles.pad)
  }

  private struct OnScreen {
    var dots: [Pt]
    var size: Float
    var area: TaliCore.Rect
  }

  private func onScreen(_ s: ShapeRow) -> OnScreen? {
    guard let b = s.geometry.bounds(s.size) else { return nil }
    let z = zoom
    let r = TaliCore.Rect(b.left * z, b.top * z, b.right * z, b.bottom * z)
    return OnScreen(dots: s.geometry.handles().map { $0 * z }, size: SelectionHandles.shapeSize(s.geometry, on: r), area: r.outset(SelectionHandles.pad))
  }

  private func rotateHandle(_ frame: TaliCore.Rect) -> Pt {
    var dots: [Pt] = []
    if selectionCount == 1, let s = activeShape, let on = onScreen(s), on.size >= SelectionHandles.tinyShape { dots = on.dots }
    return SelectionHandles.rotateHandle(frame, dots: dots)
  }

  private func chips(_ frame: TaliCore.Rect) -> [Pt] {
    [SelectionHandles.resizeChip(frame), SelectionHandles.moveChip(frame)] + (canRotate ? [rotateHandle(frame)] : [])
  }

  // MARK: Which touch edits

  /// A shape that picked itself up when it was drawn lets the pencil write inside it (she may be
  /// writing in the box she just drew); a finger still moves it, and so does the pencil with the Shapes tool.
  private func grab(at s: Pt, pencil: Bool) -> SelectionGrab? {
    guard let frame = lasso.bounds.map({ screenFrame($0) }) else { return nil }
    if SelectionHandles.resizeChip(frame).dist(s) < SelectionHandles.hit { return .resize }
    if SelectionHandles.moveChip(frame).dist(s) < SelectionHandles.hit { return .move }
    if let shape = activeShape, let on = onScreen(shape),
      let i = SelectionHandles.dot(at: s, dots: on.dots, shapeSize: on.size, area: on.area, chips: chips(frame))
    {
      return .dot(i, of: shape)
    }
    if canRotate, rotateHandle(frame).dist(s) < SelectionHandles.hit { return .turn }
    let writesThrough = lasso.soft && pencil && parent.tool != .shape
    return !writesThrough && frame.contains(s) ? .move : nil
  }

  /// Every watcher of the canvas's touches asks, in no set order, so the
  /// answer is worked out once per touch, from how things stood before any of them acted on it.
  func claim(_ t: UITouch) -> SelectionGrab? {
    let id = ObjectIdentifier(t)
    if let c = lasso.claim, c.touch == id, c.began == t.timestamp { return c.grab }
    var grab: SelectionGrab?
    if let canvas, !parent.viewOnly, textEdit.view == nil {
      grab = self.grab(at: Pt(t.location(in: canvas)), pencil: t.type == .pencil)
    }
    lasso.claim = (id, t.timestamp, grab)
    return grab
  }

  func takes(_ t: UITouch) -> Bool {
    if claim(t) != nil { return true }
    lasso.editSince = nil
    if parent.tool == .lasso { return true }
    if draws(t), lasso.bounds != nil { clearSelection() }
    return false
  }

  // MARK: Dragging

  func beginDrag(_ grab: SelectionGrab, at p: Pt) {
    guard let canvas, let b = lasso.bounds else { return }
    switch grab {
    case .resize: lasso.drag = .scale(from: p)
    case .move: lasso.drag = .move(from: p)
    case .turn: lasso.drag = .turn(from: p, pivot: Pt(CGPoint(x: b.midX, y: b.midY)), facing: selectionFacing(), angle: 0)
    case let .dot(i, shape):
      // Where on the dot she grabbed it is kept, so the shape doesn't jump to the pen tip.
      lasso.drag = .dot(index: i, grab: shape.geometry.handles()[i] - p, base: shape, live: shape)
    }
    // The pen doesn't write while it edits; should PencilKit hand a stroke in anyway, `sync` drops it.
    lasso.editSince = Date().addingTimeInterval(-0.2)
    canvas.drawingGestureRecognizer.isEnabled = false
    lasso.menuTicket += 1
    parent.onSelection(nil)
    lasso.transform = .identity
    lasso.before = canvas.drawing
    liftShapes()
    drawChrome()
  }

  func continueDrag(to p: Pt) {
    guard let canvas, let drag = lasso.drag, let b = lasso.bounds else { return }
    switch drag {
    case let .move(from): lasso.transform = .translate(p.x - from.x, p.y - from.y)
    case let .scale(from): lasso.transform = SelectionHandles.scale(TaliCore.Rect(b), from: from, to: p)
    case let .turn(from, pivot, facing, _):
      let angle = SelectionHandles.turn(about: pivot, from: from, to: p, facing: facing)
      lasso.drag = .turn(from: from, pivot: pivot, facing: facing, angle: angle)
      lasso.transform = .rotateAround(pivot, angle)
    case let .dot(index, grab, base, _):
      var live = base
      live.geometry = base.geometry.dragging(index, to: p + grab)
      lasso.drag = .dot(index: index, grab: grab, base: base, live: live)
      showLive(live)
      drawChrome()
      return
    }
    let t = lasso.transform
    if let before = lasso.before, !lasso.picked.isEmpty {
      let by = CGAffineTransform(a: CGFloat(t.a), b: CGFloat(t.b), c: CGFloat(t.c), d: CGFloat(t.d), tx: CGFloat(t.tx), ty: CGFloat(t.ty))
      loading = true
      canvas.drawing = PKDrawing(strokes: before.strokes.enumerated().map { i, s in
        guard i < stored.count, lasso.picked.contains(stored[i].stroke.id) else { return s }
        var m = s
        m.transform = s.transform.concatenating(by)
        return m
      })
      loading = false
    }
    carryShapes(t)
    drawChrome()
  }

  func endDrag(cancelled: Bool) {
    guard let canvas, let drag = lasso.drag else { return }
    let t = lasso.transform
    lasso.drag = nil
    lasso.transform = .identity
    let shapesBefore = lasso.shapesBefore ?? shapes, textsBefore = lasso.textsBefore ?? texts
    let before = lasso.before
    lasso.before = nil
    canvas.drawingGestureRecognizer.isEnabled = inkOn
    // nil leaves the menu as it was; an edit keeps it away for a moment; a tap brings it back.
    var menu: Bool?
    var changed = false
    switch drag {
    case let .dot(_, _, base, live):
      lasso.chipsBackAt = Date()
      if !cancelled, live != base {
        let after = shapesBefore.map { $0.id == live.id ? live : $0 }
        setShapes(after)
        registerShapesChange(from: shapesBefore, to: after)
        changed = true
        menu = false
      }
    case .move, .scale, .turn:
      if case .move = drag { lasso.chipsBackAt = Date() }
      if !cancelled, t != .identity, let before {
        let movedDrawing = canvas.drawing
        record(before, shapes: shapesBefore, texts: textsBefore)
        sync(movedDrawing)
        setShapes(shapesBefore.map { lasso.pickedShapes.contains($0.id) ? moved($0, by: t) : $0 })
        setTexts(textsBefore.map { lasso.pickedTexts.contains($0.id) ? $0.transformed(t) : $0 })
        if case let .turn(_, _, _, angle) = drag { noteTurn(angle) }
        reportUndo()
        changed = true
        menu = false
      } else if !cancelled {
        menu = true
      }
    }
    if !changed {
      if let before, !lasso.picked.isEmpty {
        loading = true
        canvas.drawing = before
        loading = false
      }
      restoreLifted()
    }
    dropShapes()
    setSelection(strokes: lasso.picked, shapes: lasso.pickedShapes, texts: lasso.pickedTexts, menu: menu)
  }

  private func selectionFacing() -> Float {
    func area(_ s: ShapeRow) -> Float { s.geometry.bounds(s.size).map { $0.width * $0.height } ?? 0 }
    if let own = pickedShapeRows.filter({ $0.geometry.facing != nil }).max(by: { area($0) < area($1) }), let f = own.geometry.facing { return f }
    let first = pickedStrokes.first?.id ?? pickedShapeRows.first?.id
    return first.flatMap { lasso.turnedBy[$0] } ?? 0
  }

  private func noteTurn(_ angle: Float) {
    let ids = Array(lasso.picked) + pickedShapeRows.filter { $0.geometry.facing == nil }.map(\.id)
    for id in ids { lasso.turnedBy[id] = (lasso.turnedBy[id] ?? 0) + angle }
  }

  // MARK: Picking up

  /// [menu]: true shows the selection menu, false
  /// keeps it away for a moment (she just moved, turned or reshaped it), nil leaves it as it was.
  func setSelection(strokes: Set<String>, shapes picked: Set<String>, texts pickedTexts: Set<String>, menu: Bool?) {
    let same = strokes == lasso.picked && picked == lasso.pickedShapes && pickedTexts == lasso.pickedTexts
    if !same { lasso.soft = false }
    lasso.menuClosed = menu.map { !$0 } ?? (same && lasso.menuClosed)
    lasso.picked = strokes
    lasso.pickedShapes = picked
    lasso.pickedTexts = pickedTexts
    lasso.bounds = pickedBounds()
    lasso.menuTicket += 1
    if lasso.menuClosed, lasso.bounds != nil {
      let ticket = lasso.menuTicket
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.menuBack) { [weak self] in
        guard let self, self.lasso.menuTicket == ticket, self.lasso.menuClosed, self.lasso.drag == nil else { return }
        self.lasso.menuClosed = false
        self.reportSelection()
      }
    }
    redrawSelection()
  }

  private func pickedBounds() -> CGRect? {
    var out = joined(unionOf(pickedStrokes), unionOf(pickedShapeRows))
    for t in texts where lasso.pickedTexts.contains(t.id) { out = joined(out, TextLook.frame(t)) }
    return out
  }

  func selectShape(_ shape: ShapeRow, soft: Bool = false) {
    setSelection(strokes: [], shapes: [shape.id], texts: [], menu: true)
    lasso.soft = soft
  }

  func pick(at p: Pt) {
    switch item(at: p) {
    case .stroke(let id)?: setSelection(strokes: [id], shapes: [], texts: [], menu: true)
    case .shape(let s)?: selectShape(s)
    case .text(let t)?: setSelection(strokes: [], shapes: [], texts: [t.id], menu: true)
    case nil: break
    }
  }

  /// Ink newer than [since] is left out: the dot a pen tap leaves isn't what the tap was on.
  func item(at p: Pt, since: Date? = nil) -> TappedItem? {
    let r = Self.hitRadius / zoom
    func near(_ line: [Pt], _ reach: Float) -> Bool {
      if line.count == 1 { return line[0].dist(p) <= reach }
      return line.indices.dropLast().contains { Geo.distToSegment(p, line[$0], line[$0 + 1]) <= reach }
    }
    var top: (z: Int64, item: TappedItem)?
    for (key, s) in stored where !s.tags.contains("LOCKED") && s.bounds.outset(r).contains(p) {
      if let since, key.created >= since.timeIntervalSinceReferenceDate { continue }
      guard near(s.inputs.points.map { Pt($0.x, $0.y) }, r + s.size / 2) else { continue }
      if top.map({ s.z >= $0.z }) ?? true { top = (s.z, .stroke(s.id)) }
    }
    for sh in shapes where !sh.locked {
      guard let b = sh.geometry.bounds(sh.size), b.outset(r).contains(p), sh.geometry.paths(sh.size).contains(where: { near($0, r + sh.size / 2) }) else { continue }
      if top.map({ sh.z >= $0.z }) ?? true { top = (sh.z, .shape(sh)) }
    }
    if let top { return top.item }
    return texts.last { !$0.locked && TextLook.frame($0).contains(CGPoint(p)) }.map(TappedItem.text)
  }

  // MARK: Drawing it

  func drawChrome() {
    guard let canvas else { return }
    var c = SelectionChrome()
    defer { lasso.chrome.show(c, over: canvas) }
    guard let b = lasso.bounds else { return }
    let z = zoom
    let idle = screenFrame(b)
    let shape = activeShape
    let alone = shape != nil && selectionCount == 1
    // On whole pixels, so all four dashed edges look equally crisp.
    func box(_ r: TaliCore.Rect) -> CGRect { CGRect(r).integral.insetBy(dx: 0.5, dy: 0.5) }
    var reshaping: Int?
    switch lasso.drag {
    case let .turn(_, pivot, facing, angle)?:
      let pad = SelectionHandles.pad / z
      let l = Float(b.minX) - pad, t = Float(b.minY) - pad, r = Float(b.maxX) + pad, bottom = Float(b.maxY) + pad
      c.outline = [Pt(l, t), Pt(r, t), Pt(r, bottom), Pt(l, bottom)].map { CGPoint(lasso.transform.apply($0) * z) }
      var line = false
      if alone, case .line? = shape?.geometry { line = true }
      c.angle = Measure.Badge(label: "\(SelectionHandles.turnDegrees(facing + angle, line: line))°", at: pivot * z)
      return
    case .scale?:
      let r = screenFrame(b, by: lasso.transform)
      c.frame = box(r)
      c.resizeChip = CGPoint(SelectionHandles.resizeChip(r))
      if alone, let g = shape?.geometry.transformed(lasso.transform) { c.hints = squareHint(g, circleDot: false) }
      return
    case .move?:
      if !alone { c.frame = box(screenFrame(b, by: lasso.transform)) }
      return
    case let .dot(index, _, _, _)?: reshaping = index
    case nil: break
    }
    if !alone { c.frame = box(idle) }
    if reshaping == nil {
      c.resizeChip = CGPoint(SelectionHandles.resizeChip(idle))
      c.moveChip = CGPoint(SelectionHandles.moveChip(idle))
      c.chipsBackAt = lasso.chipsBackAt
      if canRotate { c.rotate = (CGPoint(rotateHandle(idle)), CGFloat(idle.bottom)) }
    }
    guard alone, let shape, let on = onScreen(shape) else { return }
    // Smaller dots on a small shape; none on a tiny one (it's moved and resized whole).
    if on.size >= SelectionHandles.tinyShape || reshaping != nil {
      c.dots = on.dots.map { CGPoint($0) }
      c.dotRadius = CGFloat(SelectionHandles.dotRadius(shapeSize: on.size))
    }
    let origin = Pt(canvas.bounds.origin)
    let avoid = chips(idle).map { (at: $0 - origin, radius: Float(17)) } + on.dots.map { (at: $0 - origin, radius: Float(10)) }
    let menu = reshaping == nil ? TaliCore.Rect(idle.center.x - 130 - origin.x, idle.top - 70 - origin.y, idle.center.x + 130 - origin.x, idle.top - 2 - origin.y) : nil
    let phase: Measure.Phase = reshaping.map { .changing(dot: $0) } ?? .idle(frame: idle)
    c.badges = Measure.badges(shape.geometry, phase, toScreen: { $0 * z }, width: SelectionChromeView.badgeWidth).map { badge in
      let spot = Measure.clearSpot(
        badge.at - origin, w: SelectionChromeView.badgeWidth(badge.label), h: Measure.badgeHeight,
        screen: (Float(canvas.bounds.width), Float(canvas.bounds.height)), avoid: avoid, menu: menu)
      return Measure.Badge(label: badge.label, at: spot + origin)
    }
    c.hints = radiusHint(shape.geometry, dot: reshaping) + (reshaping == nil ? [] : squareHint(shape.geometry, circleDot: true))
  }

  /// So she can see it locked on square or round. A circle's own dot shows its radius instead.
  private func squareHint(_ g: ShapeGeometry, circleDot: Bool) -> [(from: CGPoint, to: CGPoint, centre: Bool)] {
    let z = zoom
    if g.isSquare, case let .poly(points, _, _, _, _) = g { return [(CGPoint(points[0] * z), CGPoint(points[2] * z), false)] }
    if g.round, case let .ellipse(_, rx, _, _, _) = g, rx > 4, !(circleDot && g.isCircle) {
      return [(CGPoint(g.ellipsePoint(0.75 * .pi) * z), CGPoint(g.ellipsePoint(1.75 * .pi) * z), false)]
    }
    return []
  }

  private func radiusHint(_ g: ShapeGeometry, dot: Int?) -> [(from: CGPoint, to: CGPoint, centre: Bool)] {
    let z = zoom
    let ends: (Pt, Pt)
    switch g {
    case let .ellipse(center, _, _, _, _) where g.isCircle: ends = (center, g.ellipsePoint(0))
    case let .sector(center, _, _, _) where dot == 2: ends = (center, g.handles()[2])
    case let .arc(center, _, _, _, false) where dot == 2: ends = (center, g.handles()[2])
    default: return []
    }
    if ends.0.dist(ends.1) * z < SelectionHandles.tinyShape / 2 { return [] }
    return [(CGPoint(ends.0 * z), CGPoint(ends.1 * z), true)]
  }
}
