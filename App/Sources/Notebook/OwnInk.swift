import PencilKit
import TaliCore
import UIKit

/// What the notebook draws itself instead of PencilKit, decided when the pen or finger lands:
/// PencilKit has no laser, no dashes, no straight-line highlighter and no eraser that knows pen types.
enum OwnInk {
  case laser
}

struct OwnInkState {
  var watcher: StrokeWatcher?
  /// What the touch on the page is doing, from when it landed until it lifts.
  var mode: OwnInk?
  var laser = LaserState()
}

extension NoteCanvas.Coordinator {
  /// What the tool in use draws by itself, or nil when PencilKit writes (or the tool has its own watcher).
  var ownInk: OwnInk? {
    guard !parent.viewOnly else { return nil }
    switch parent.tool {
    case .laser: return .laser
    default: return nil
    }
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
  }

  /// The pen always draws; a finger only where fingers draw.
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
    case nil: break
    }
  }

  private func ownMoved(_ t: UITouch, _ e: UIEvent) {
    let samples = e.coalescedTouches(for: t) ?? [t]
    switch own.mode {
    case .laser: laserMoved(samples.map(worldPoint(of:)))
    case nil: break
    }
  }

  private func ownEnded(_ cancelled: Bool) {
    switch own.mode {
    case .laser: laserEnded()
    case nil: break
    }
    own.mode = nil
  }
}
