import PencilKit
import TaliCore
import UIKit

/// The resize chip (Android's `resizeChip`, `drawResizeChip`, `Mode.SCALE_SELECTION`): a white round
/// chip with a diagonal two-way arrow just off the selection's bottom-right corner. Dragging it
/// scales everything picked up about the selection's top-left corner, its far side or middle lining
/// up with nearby shapes; one undo step on letting go.
extension NoteCanvas.Coordinator {
  /// How far out from the frame the chip sits, its radius and how far a touch reaches it (points on screen).
  private static let chipOffset: CGFloat = 14
  private static let chipRadius: CGFloat = 13
  private static let chipHit: CGFloat = 24

  func installResizeChip(on v: PKCanvasView) {
    let l = lasso.chipLayer
    l.zPosition = 11
    l.fillColor = UIColor.white.cgColor
    l.strokeColor = UIColor(argb: Int32(bitPattern: 0xFF4F_7BE8)).cgColor
    l.lineWidth = 2
    l.shadowColor = UIColor.black.cgColor
    l.shadowOpacity = 0.12
    l.shadowRadius = 3
    l.shadowOffset = CGSize(width: 0, height: 1)
    let arrow = lasso.chipArrow
    arrow.fillColor = nil
    arrow.strokeColor = l.strokeColor
    arrow.lineWidth = 1.8
    arrow.lineCap = .round
    arrow.lineJoin = .round
    l.addSublayer(arrow)
    v.layer.addSublayer(l)
    // The move chip, styled the same.
    let m = lasso.moveChipLayer
    m.zPosition = 11
    m.fillColor = l.fillColor
    m.strokeColor = l.strokeColor
    m.lineWidth = l.lineWidth
    m.shadowColor = l.shadowColor
    m.shadowOpacity = l.shadowOpacity
    m.shadowRadius = l.shadowRadius
    m.shadowOffset = l.shadowOffset
    let mArrow = lasso.moveChipArrow
    mArrow.fillColor = nil
    mArrow.strokeColor = l.strokeColor
    mArrow.lineWidth = 1.6
    mArrow.lineCap = .round
    mArrow.lineJoin = .round
    m.addSublayer(mArrow)
    v.layer.addSublayer(m)
  }

  /// Where the move chip's middle is (content coordinates): off the frame's bottom-left corner.
  private func moveChipCentre(_ b: CGRect) -> CGPoint {
    let z = canvas?.zoomScale ?? 1
    let r = CGRect(x: b.minX * z, y: b.minY * z, width: b.width * z, height: b.height * z).insetBy(dx: -8, dy: -8)
    return CGPoint(x: r.minX - Self.chipOffset, y: r.maxY + Self.chipOffset)
  }

  /// Whether a touch at [p] (world units) lands on the move chip: dragging it moves the selection,
  /// handy for shapes that are mostly lines, where grabbing the shape itself is fiddly.
  func onMoveChip(_ p: CGPoint) -> Bool {
    guard let canvas, !parent.viewOnly, let b = lasso.bounds, !lasso.moveChipLayer.isHidden else { return false }
    let z = canvas.zoomScale
    let c = moveChipCentre(b)
    return hypot(p.x * z - c.x, p.y * z - c.y) < Self.chipHit
  }

  /// The chips come back after a move or a dot drag quickly: a fade and a small grow (Android's `CHIP_BACK_MS`, 160 ms).
  private func fadeBack(_ l: CALayer) {
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    let grow = CABasicAnimation(keyPath: "transform.scale")
    grow.fromValue = 0.85
    grow.toValue = 1
    let g = CAAnimationGroup()
    g.animations = [fade, grow]
    g.duration = 0.16
    g.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    l.add(g, forKey: "back")
  }

  /// Where the chip's middle is, in the canvas's content coordinates, for selection bounds [b] (world units).
  private func chipCentre(_ b: CGRect) -> CGPoint {
    let z = canvas?.zoomScale ?? 1
    let r = CGRect(x: b.minX * z, y: b.minY * z, width: b.width * z, height: b.height * z).insetBy(dx: -8, dy: -8)
    return CGPoint(x: r.maxX + Self.chipOffset, y: r.maxY + Self.chipOffset)
  }

  /// Draws the chip beside [b] (nil hides it).
  func drawResizeChip(_ b: CGRect?) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    drawRotateHandle(b)
    guard let b, !lasso.moving, lasso.handle == nil, !parent.viewOnly, !rotate.active else {
      lasso.chipLayer.isHidden = true
      lasso.moveChipLayer.isHidden = true
      return
    }
    let c = chipCentre(b)
    let r = Self.chipRadius
    let wasHidden = lasso.chipLayer.isHidden
    lasso.chipLayer.isHidden = false
    drawMoveChip(b, comingBack: wasHidden)
    if wasHidden { fadeBack(lasso.chipLayer) }
    lasso.chipLayer.frame = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    lasso.chipLayer.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)).cgPath
    let a: CGFloat = 4.6, h: CGFloat = 3.2
    let m = CGPoint(x: r, y: r)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: m.x - a, y: m.y - a))
    p.addLine(to: CGPoint(x: m.x + a, y: m.y + a))
    p.move(to: CGPoint(x: m.x - a + h, y: m.y - a))
    p.addLine(to: CGPoint(x: m.x - a, y: m.y - a))
    p.addLine(to: CGPoint(x: m.x - a, y: m.y - a + h))
    p.move(to: CGPoint(x: m.x + a - h, y: m.y + a))
    p.addLine(to: CGPoint(x: m.x + a, y: m.y + a))
    p.addLine(to: CGPoint(x: m.x + a, y: m.y + a - h))
    lasso.chipArrow.path = p
  }

  /// The move chip: a four-way arrow, an arrowhead on each end (Android's `drawMoveChip`). Not while resizing.
  private func drawMoveChip(_ b: CGRect, comingBack: Bool) {
    let l = lasso.moveChipLayer
    guard !lasso.scaling else {
      l.isHidden = true
      return
    }
    let wasHidden = l.isHidden
    let c = moveChipCentre(b)
    let r = Self.chipRadius
    l.isHidden = false
    l.frame = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    l.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)).cgPath
    let a: CGFloat = 7.2, h: CGFloat = 2.1
    let m = CGPoint(x: r, y: r)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: m.x - a, y: m.y))
    p.addLine(to: CGPoint(x: m.x + a, y: m.y))
    p.move(to: CGPoint(x: m.x, y: m.y - a))
    p.addLine(to: CGPoint(x: m.x, y: m.y + a))
    for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] as [(CGFloat, CGFloat)] {
      let tx = m.x + dx * a, ty = m.y + dy * a
      p.move(to: CGPoint(x: tx - dx * h - dy * h, y: ty - dy * h - dx * h))
      p.addLine(to: CGPoint(x: tx, y: ty))
      p.addLine(to: CGPoint(x: tx - dx * h + dy * h, y: ty - dy * h + dx * h))
    }
    lasso.moveChipArrow.path = p
    if wasHidden || comingBack { fadeBack(l) }
  }

  /// A touch landing at [p] (world units) on the chip starts resizing what's picked up.
  func beginResize(at p: CGPoint) -> Bool {
    guard let canvas, !parent.viewOnly, let b = lasso.bounds else { return false }
    let z = canvas.zoomScale
    let c = chipCentre(b)
    guard hypot(p.x * z - c.x, p.y * z - c.y) < Self.chipHit else { return false }
    lasso.scaling = true
    lasso.moveChipLayer.isHidden = true
    lasso.scaleBy = 1
    lasso.moveStart = p
    lasso.scaleBounds = b
    lasso.before = canvas.drawing
    startMoveSnap()
    liftShapes()
    parent.onSelection(nil)
    lasso.dotsLayer.path = nil
    return true
  }

  /// The chip dragged to [p] (world units).
  func resize(to p: CGPoint) {
    guard let canvas, let b = lasso.scaleBounds, let before = lasso.before else { return }
    let anchor = CGPoint(x: b.minX, y: b.minY)
    var s = Float(min(max(hypot(p.x - anchor.x, p.y - anchor.y) / max(1, hypot(lasso.moveStart.x - anchor.x, lasso.moveStart.y - anchor.y)), 0.1), 10))
    // Its far side or middle lines up with nearby shapes as it grows or shrinks.
    if let m = lasso.snapMoving, let box = m.box, let snap = lasso.snap {
      let z = Float(canvas.zoomScale)
      snap.begin(contact: Self.snapPt / z, align: Self.alignPt / z)
      let (snapped, guides) = Snap.scale(box, Pt(Float(anchor.x), Float(anchor.y)), s, lasso.snapTargets, snap, middleOnly: m.middleOnly)
      s = min(max(snapped, 0.1), 10)
      showSnap(guides)
    }
    if hypot(b.width, b.height) * CGFloat(s) < 4 { s = 1 }
    lasso.scaleBy = s
    let t = Self.scaleAbout(anchor, CGFloat(s))
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
    lasso.shapeLayer.setAffineTransform(Self.scaleAbout(CGPoint(x: anchor.x * z, y: anchor.y * z), CGFloat(s)))
    CATransaction.commit()
    let nb = b.applying(t)
    redrawFrameOnly(nb)
    drawResizeChip(nb)
  }

  /// Lets go of the chip: the new size is kept, one undo step.
  func endResize() {
    guard let canvas, let b = lasso.scaleBounds else { return }
    lasso.scaling = false
    let s = lasso.scaleBy
    lasso.snap = nil
    lasso.snapMoving = nil
    showSnap([])
    let shapesBefore = lasso.shapesBefore ?? shapes
    let textsBefore = lasso.textsBefore ?? texts
    if let before = lasso.before, abs(s - 1) > 0.001 {
      let anchor = Pt(Float(b.minX), Float(b.minY))
      let m = Affine.scaleAround(anchor, s)
      let scaledDrawing = canvas.drawing
      record(before, shapes: shapesBefore, texts: textsBefore)
      sync(scaledDrawing)
      setShapes(shapesBefore.map { lasso.pickedShapes.contains($0.id) ? moved($0, by: m) : $0 })
      setTexts(textsBefore.map { t in
        guard lasso.pickedTexts.contains(t.id) else { return t }
        // Android's TextItem.transformed: the box and its letters scale together.
        var c = t
        let o = m.apply(Pt(t.x, t.y))
        c.x = o.x
        c.y = o.y
        c.width = max(t.width * s, 40)
        c.fontSize = min(max(t.fontSize * s, 6), 400)
        c.height = t.height * s
        return c
      })
      lasso.bounds = b.applying(Self.scaleAbout(CGPoint(x: b.minX, y: b.minY), CGFloat(s)))
      reportUndo()
    } else {
      setShapes(shapesBefore)
      setTexts(textsBefore)
    }
    dropShapes()
    lasso.before = nil
    lasso.scaleBounds = nil
    redrawSelection()
  }

  static func scaleAbout(_ a: CGPoint, _ s: CGFloat) -> CGAffineTransform {
    CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: a.x * (1 - s), ty: a.y * (1 - s))
  }
}
