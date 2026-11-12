import PencilKit
import TaliCore
import UIKit

/// The rotate handle (Android's `rotateHandle`, `drawRotateHandle`, `Mode.ROTATE_SELECTION`): a small
/// round handle with a turning arrow hanging below the middle of the selection (lower still when one
/// of the shape's own dots sits there). Dragging it turns everything picked up about its middle,
/// snapping to 45° steps by the way it faces on the page, with the angle in a badge at the middle;
/// one undo step on letting go. Not offered when a text box is picked up (as Android: no pictures or text).
struct RotateState {
  var active = false
  var pivot = CGPoint.zero
  var start = CGPoint.zero
  var angle: Float = 0
  /// How far the selection faced from level when this turn began (radians, y down).
  var base: Float = 0
  /// How far things with no direction of their own (handwriting, arcs) were turned this session.
  var turnedBy: [String: Float] = [:]
  let stem = CAShapeLayer()
  let handle = CAShapeLayer()
  let arrow = CAShapeLayer()
  let badge = CALayer()
  let badgeText = CATextLayer()
}

extension NoteCanvas.Coordinator {
  private static let rotateDrop: CGFloat = 30
  private static let rotateRadius: CGFloat = 6.5
  private static let rotateHit: CGFloat = 24
  /// Android's `SNAP_ROTATE_RAD`: within 5° of a 45° step it settles on it.
  private static let rotateSnap: Float = 0.087

  private var handleBlue: UIColor { UIColor(argb: Int32(bitPattern: 0xFF4F_7BE8)) }
  private var accentColor: UIColor { UIColor(argb: Int32(bitPattern: 0xFF7A_4ED6)) }

  func installRotateHandle(on v: PKCanvasView) {
    let r = rotate
    r.stem.fillColor = nil
    r.stem.strokeColor = accentColor.cgColor
    r.stem.lineWidth = 1.5
    r.stem.lineDashPattern = [6, 4]
    r.stem.zPosition = 10
    r.handle.fillColor = UIColor.white.cgColor
    r.handle.strokeColor = handleBlue.cgColor
    r.handle.lineWidth = 2
    r.handle.shadowColor = UIColor.black.cgColor
    r.handle.shadowOpacity = 0.12
    r.handle.shadowRadius = 2
    r.handle.shadowOffset = CGSize(width: 0, height: 1)
    r.handle.zPosition = 11
    r.arrow.fillColor = nil
    r.arrow.strokeColor = handleBlue.cgColor
    r.arrow.lineWidth = 1.5
    r.arrow.lineCap = .round
    r.handle.addSublayer(r.arrow)
    r.badge.backgroundColor = handleBlue.cgColor
    r.badge.zPosition = 12
    r.badgeText.foregroundColor = UIColor.white.cgColor
    r.badgeText.alignmentMode = .center
    r.badgeText.fontSize = 13
    r.badgeText.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    r.badgeText.contentsScale = v.traitCollection.displayScale
    r.badge.addSublayer(r.badgeText)
    for l in [r.stem, r.handle, r.badge] as [CALayer] {
      l.isHidden = true
      v.layer.addSublayer(l)
    }
  }

  /// Whether what's picked up can be turned (Android's `canRotateSelection`).
  var canRotate: Bool {
    (!lasso.picked.isEmpty || !lasso.pickedShapes.isEmpty) && lasso.pickedTexts.isEmpty && !parent.viewOnly
  }

  /// The selection's frame on screen (content coordinates), as the frame is drawn.
  private func frameRect(_ b: CGRect) -> CGRect {
    let z = canvas?.zoomScale ?? 1
    return CGRect(x: b.minX * z, y: b.minY * z, width: b.width * z, height: b.height * z).insetBy(dx: -8, dy: -8)
  }

  /// Where the handle's middle is (content coordinates): below the frame's middle, and below any of
  /// a lone shape's own dots that sit under the middle (a lever's fulcrum), so the two never meet.
  private func rotateHandleCentre(_ b: CGRect) -> CGPoint {
    let r = frameRect(b)
    var y = r.maxY + Self.rotateDrop
    if lasso.picked.isEmpty, lasso.pickedShapes.count == 1, let s = pickedShapeRows.first {
      let z = canvas?.zoomScale ?? 1
      let under = s.geometry.handles().map { CGPoint(x: CGFloat($0.x) * z, y: CGFloat($0.y) * z) }
        .filter { abs($0.x - r.midX) < Self.rotateHit * 1.5 && $0.y > r.maxY - Self.rotateHit }
        .map(\.y).max()
      if let under { y = max(y, under + Self.rotateDrop) }
    }
    return CGPoint(x: r.midX, y: y)
  }

  /// Draws the handle under [b], or hides it (nil, or while moving, resizing or dragging a dot).
  func drawRotateHandle(_ b: CGRect?) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    let r = rotate
    guard let b, canRotate, !lasso.moving, !lasso.scaling, lasso.handle == nil, !r.active else {
      r.stem.isHidden = true
      r.handle.isHidden = true
      return
    }
    let f = frameRect(b)
    let h = rotateHandleCentre(b)
    let rad = Self.rotateRadius
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: h.x, y: f.maxY))
    stem.addLine(to: CGPoint(x: h.x, y: h.y - rad))
    r.stem.path = stem
    r.stem.isHidden = false
    r.handle.frame = CGRect(x: h.x - rad, y: h.y - rad, width: 2 * rad, height: 2 * rad)
    r.handle.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 2 * rad, height: 2 * rad)).cgPath
    // A little turning arrow inside (Android: an arc from −60° round 280°).
    let a: CGFloat = 3.2
    r.arrow.path = UIBezierPath(arcCenter: CGPoint(x: rad, y: rad), radius: a, startAngle: -.pi / 3, endAngle: -.pi / 3 + 280 * .pi / 180, clockwise: true).cgPath
    r.handle.isHidden = false
  }

  /// A touch at [p] (world units) on the handle starts turning what's picked up.
  func beginRotate(at p: CGPoint) -> Bool {
    guard let canvas, canRotate, let b = lasso.bounds, !rotate.handle.isHidden else { return false }
    let z = canvas.zoomScale
    let h = rotateHandleCentre(b)
    guard hypot(p.x * z - h.x, p.y * z - h.y) < Self.rotateHit else { return false }
    rotate.active = true
    rotate.pivot = CGPoint(x: b.midX, y: b.midY)
    rotate.start = p
    rotate.angle = 0
    rotate.base = selectionFacing()
    lasso.before = canvas.drawing
    liftShapes()
    parent.onSelection(nil)
    lasso.dotsLayer.path = nil
    drawResizeChip(nil)
    drawRotateHandle(nil)
    showRotation()
    return true
  }

  /// The handle dragged to [p] (world units).
  func rotateTo(_ p: CGPoint) {
    guard let canvas, let before = lasso.before, rotate.active else { return }
    let c = rotate.pivot
    let start = Float(atan2(rotate.start.y - c.y, rotate.start.x - c.x))
    var angle = Float(atan2(p.y - c.y, p.x - c.x)) - start
    // 45° steps by the way it faces on the page, so it lands level, upright or diagonal however it started.
    let step = Float.pi / 4
    let snapped = ((rotate.base + angle) / step).rounded() * step - rotate.base
    if abs(angle - snapped) < Self.rotateSnap { angle = snapped }
    if angle != rotate.angle, abs(angle - snapped) < 0.0001, abs(rotate.angle - snapped) > 0.0001 {
      UISelectionFeedbackGenerator().selectionChanged()
    }
    rotate.angle = angle
    let t = Self.rotateAbout(c, CGFloat(angle))
    loading = true
    canvas.drawing = PKDrawing(strokes: before.strokes.enumerated().map { i, st in
      guard i < stored.count, lasso.picked.contains(stored[i].stroke.id) else { return st }
      var m = st
      m.transform = st.transform.concatenating(t)
      return m
    })
    loading = false
    let z = canvas.zoomScale
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lasso.shapeLayer.setAffineTransform(Self.rotateAbout(CGPoint(x: c.x * z, y: c.y * z), CGFloat(angle)))
    CATransaction.commit()
    showRotation()
  }

  /// Lets go of the handle: the turn is kept, one undo step.
  func endRotate() {
    guard let canvas, rotate.active else { return }
    rotate.active = false
    let angle = rotate.angle
    let shapesBefore = lasso.shapesBefore ?? shapes
    let textsBefore = lasso.textsBefore ?? texts
    hideRotation()
    if let before = lasso.before, abs(angle) > 0.0001 {
      let c = rotate.pivot
      let m = Affine.rotateAround(Pt(Float(c.x), Float(c.y)), angle)
      // What has no way of its own remembers how far it was turned, for the badge next time.
      for id in lasso.picked { rotate.turnedBy[id, default: 0] += angle }
      for s in shapesBefore where lasso.pickedShapes.contains(s.id) && Self.facing(s.geometry) == nil {
        rotate.turnedBy[s.id, default: 0] += angle
      }
      let turned = canvas.drawing
      record(before, shapes: shapesBefore, texts: textsBefore)
      sync(turned)
      setShapes(shapesBefore.map { lasso.pickedShapes.contains($0.id) ? moved($0, by: m) : $0 })
      lasso.bounds = joined(unionOf(stored.map(\.stroke).filter { lasso.picked.contains($0.id) }), unionOf(pickedShapeRows))
      reportUndo()
    } else {
      setShapes(shapesBefore)
    }
    dropShapes()
    lasso.before = nil
    redrawSelection()
  }

  /// The turning frame and the angle badge at its middle (Android's `drawRotatingSelection`).
  private func showRotation() {
    guard let canvas, let b = lasso.bounds else { return }
    let z = canvas.zoomScale
    let pad = 8 / z
    let c = rotate.pivot
    let t = Self.rotateAbout(c, CGFloat(rotate.angle))
    let corners = [CGPoint(x: b.minX - pad, y: b.minY - pad), CGPoint(x: b.maxX + pad, y: b.minY - pad), CGPoint(x: b.maxX + pad, y: b.maxY + pad), CGPoint(x: b.minX - pad, y: b.maxY + pad)]
      .map { $0.applying(t) }.map { CGPoint(x: $0.x * z, y: $0.y * z) }
    let path = CGMutablePath()
    path.addLines(between: corners)
    path.closeSubpath()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lasso.frameLayer.path = path
    // Counter-clockwise reads as positive, as in maths class; measured from the page.
    let line = lasso.picked.isEmpty && lasso.pickedShapes.count == 1 && pickedShapeRows.first.map { Self.isLine($0.geometry) } == true
    let raw = Int((-(rotate.base + rotate.angle) * 180 / .pi).rounded())
    let degrees = line ? ((raw % 180) + 180) % 180 : (((raw + 180) % 360) + 360) % 360 - 180
    let label = "\(degrees)°"
    let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    let w = (label as NSString).size(withAttributes: [.font: font]).width + 16
    let h: CGFloat = 24
    rotate.badge.frame = CGRect(x: c.x * z - w / 2, y: c.y * z - h / 2, width: w, height: h)
    rotate.badge.cornerRadius = h / 2
    rotate.badgeText.string = label
    rotate.badgeText.frame = CGRect(x: 0, y: (h - font.lineHeight) / 2, width: w, height: font.lineHeight)
    rotate.badge.isHidden = false
    CATransaction.commit()
  }

  private func hideRotation() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    rotate.badge.isHidden = true
    CATransaction.commit()
  }

  /// Which way a shape faces on the page (radians, y down), or nil when it has no way of its own (Android's `facing`).
  static func facing(_ g: ShapeGeometry) -> Float? {
    switch g {
    case let .line(a, b, _, _, _): (b - a).angle()
    case let .load(a, b, depth, _): (b - a).angle() + (depth < 0 ? .pi : 0)
    case let .poly(_, _, _, rotation, _): rotation
    case let .ellipse(_, _, _, rotation, _): rotation
    case let .triangle(_, _, _, turn): turn
    case let .group(_, turn): turn
    case let .param(q): q.place.mapAngle(0)
    case let .curve(points): points.count > 1 ? (points[points.count - 1] - points[0]).angle() : nil
    default: nil
    }
  }

  /// The angle the turning badge starts from: the biggest shape's own, else what this session turned it by.
  private func selectionFacing() -> Float {
    let own = pickedShapeRows.filter { Self.facing($0.geometry) != nil }
      .max { a, b in
        let ra = a.geometry.bounds(a.size), rb = b.geometry.bounds(b.size)
        return (ra.map { $0.width * $0.height } ?? 0) < (rb.map { $0.width * $0.height } ?? 0)
      }
    if let own, let f = Self.facing(own.geometry) { return f }
    let first = stored.first { lasso.picked.contains($0.stroke.id) }?.stroke.id ?? pickedShapeRows.first?.id
    return first.flatMap { rotate.turnedBy[$0] } ?? 0
  }

  private static func isLine(_ g: ShapeGeometry) -> Bool {
    if case .line = g { return true }
    return false
  }

  static func rotateAbout(_ c: CGPoint, _ a: CGFloat) -> CGAffineTransform {
    CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a).translatedBy(x: -c.x, y: -c.y)
  }
}
