import PencilKit
import TaliCore
import UIKit

/// What the notebook draws itself because PencilKit can't: the laser, the highlighter's straight
/// line, and strokes shaped by an `InkLook`.
enum OwnInk {
  case laser
  case straight(PenSlot, InkLook)
  case trace(PenSlot, InkLook)
}

struct OwnInkState {
  var watcher: StrokeWatcher?
  /// Fixed when the touch lands, so changing pens mid-stroke can't change what it writes.
  var mode: OwnInk?
  var laser = LaserState()
  var samples: [InkInput] = []
  var start = Pt.zero
  var end = Pt.zero
  var startTime: TimeInterval = 0
  var began = Date()
  let live = CAShapeLayer()
  let liveClip = CAShapeLayer()
}

extension NoteCanvas.Coordinator {
  /// Nil when PencilKit writes, or the tool has a watcher of its own.
  var ownInk: OwnInk? {
    guard !parent.viewOnly else { return nil }
    switch parent.tool {
    case .laser: return .laser
    case .pen(let id):
      guard let pen = parent.pens.first(where: { $0.id == id }), let look = InkLook(pen) else { return nil }
      return pen.straight ? .straight(pen, look) : .trace(pen, look)
    default: return nil
    }
  }

  var tracesOwnInk: Bool {
    if case .trace = ownInk { return true }
    return false
  }

  func installOwnInk(on v: PKCanvasView) {
    let w = StrokeWatcher(target: nil, action: nil)
    w.delegate = self
    w.accepts = { [weak self] t in self.map { $0.ownInk != nil && $0.touchDraws(t) } ?? false }
    w.began = { [weak self] t, _ in self?.ownBegan(t) }
    w.moved = { [weak self] t, e in self?.ownMoved(t, e) }
    w.ended = { [weak self] cancelled in self?.ownEnded(cancelled) }
    v.addGestureRecognizer(w)
    // One finger or the pen draws; scrolling waits until it's clear this touch doesn't.
    v.panGestureRecognizer.require(toFail: w)
    own.watcher = w
    own.laser.layer.zPosition = 11
    v.layer.addSublayer(own.laser.layer)
    own.live.zPosition = 8
    own.live.strokeColor = nil
    v.layer.addSublayer(own.live)
  }

  func touchDraws(_ t: UITouch) -> Bool {
    guard let canvas else { return false }
    if t.type == .pencil { return true }
    switch canvas.drawingPolicy {
    case .anyInput: return true
    case .pencilOnly: return false
    default: return !UIPencilInteraction.prefersPencilOnlyDrawing
    }
  }

  func worldPoint(of t: UITouch) -> Pt {
    guard let canvas else { return .zero }
    let p = t.location(in: canvas)
    return Pt(Float(p.x / canvas.zoomScale), Float(p.y / canvas.zoomScale))
  }

  private func ownBegan(_ t: UITouch) {
    own.mode = ownInk
    switch own.mode {
    case .laser: laserBegan(worldPoint(of: t))
    case .straight(let pen, let look):
      own.start = worldPoint(of: t)
      own.end = StraightLine.end(from: own.start, to: own.start)
      startLive(pen, at: own.start)
      showLive(look, pen, [own.start, own.end])
    case .trace(let pen, let look):
      own.startTime = t.timestamp
      own.began = Date()
      own.samples = [sample(t)]
      startLive(pen, at: worldPoint(of: t))
      showLive(look, pen, [worldPoint(of: t)])
    case nil: break
    }
  }

  private func ownMoved(_ t: UITouch, _ e: UIEvent) {
    let touches = e.coalescedTouches(for: t) ?? [t]
    switch own.mode {
    case .laser: laserMoved(touches.map(worldPoint(of:)))
    case .straight(let pen, let look):
      own.end = StraightLine.end(from: own.start, to: worldPoint(of: touches.last ?? t))
      showLive(look, pen, [own.start, own.end])
    case .trace(let pen, let look):
      own.samples += touches.map(sample)
      // The stroke just became a shape (hold-to-shape draws that): this one isn't shown any more.
      if hold.live != nil {
        clearLive()
        return
      }
      // Where the pen is about to be, so the line keeps up with it; only what it really did is kept.
      showLive(look, pen, own.samples.map { Pt($0.x, $0.y) } + (e.predictedTouches(for: t) ?? []).map(worldPoint(of:)))
    case nil: break
    }
  }

  private func ownEnded(_ cancelled: Bool) {
    let mode = own.mode
    own.mode = nil
    clearLive()
    switch mode {
    case .laser: laserEnded()
    case .straight(let pen, _):
      if !cancelled { keep(pen, StraightLine.inputs(own.start, own.end)) }
    case .trace(let pen, _):
      let becameShape = hold.dropSince.map { own.began >= $0 } ?? false
      if !cancelled, !becameShape { keep(pen, InkInputs(points: own.samples, tool: .stylus)) }
      own.samples = []
    case nil: break
    }
  }

  /// One pen sample as Android keeps them (see `InkStroke.from`): seconds since the stroke began,
  /// half of Apple's force as pressure, the tilt from upright and the way the pencil leans.
  private func sample(_ t: UITouch) -> InkInput {
    let p = worldPoint(of: t)
    let lean = t.type == .pencil ? t.azimuthAngle(in: canvas) : 0
    return InkInput(
      x: p.x, y: p.y, t: Float(max(t.timestamp - own.startTime, 0)), pressure: t.type == .pencil ? Float(min(max(t.force / 2, 0), 1)) : 0.5,
      tilt: Float(max(0, .pi / 2 - t.altitudeAngle)), orientation: Float(lean < 0 ? lean + 2 * .pi : lean))
  }

  /// The colour PencilKit will show once the stroke is kept, hidden past the page it started on as
  /// the kept stroke will be.
  private func startLive(_ pen: PenSlot, at p: Pt) {
    guard let canvas else { return }
    let z = canvas.zoomScale
    let color = UIColor(argb: pen.inkColor)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    own.live.fillColor = (parent.settings.dark ? PKInkingTool.convertColor(color, from: .light, to: .dark) : color).cgColor
    if let page = pageClip(startingAt: p.y) {
      own.liveClip.path = CGPath(rect: CGRect(x: page.minX * z, y: page.minY * z, width: page.width * z, height: page.height * z), transform: nil)
      own.live.mask = own.liveClip
    } else {
      own.live.mask = nil
    }
    CATransaction.commit()
  }

  private func showLive(_ look: InkLook, _ pen: PenSlot, _ points: [Pt]) {
    guard let canvas else { return }
    let z = canvas.zoomScale
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    own.live.path = look.outline(size: CGFloat(pen.size) * z, points: points.map { CGPoint(x: CGFloat($0.x) * z, y: CGFloat($0.y) * z) })
    CATransaction.commit()
  }

  private func clearLive() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    own.live.path = nil
    CATransaction.commit()
  }

  private func keep(_ pen: PenSlot, _ inputs: InkInputs) {
    guard let canvas, !inputs.points.isEmpty else { return }
    let stroke = InkStroke(id: newId(), z: 0, pen: pen.type, tags: InkStroke.tags(for: pen), color: pen.inkColor, size: pen.size, inputs: inputs)
    let before = canvas.drawing
    let pk = stroke.pkStroke(mask: mask(for: stroke))
    pending[StrokeKey(pk)] = stroke
    record(before)
    canvas.drawing = PKDrawing(strokes: before.strokes + [pk])
    reportUndo()
  }
}
