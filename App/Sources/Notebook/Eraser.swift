import PencilKit
import TaliCore
import UIKit

struct EraserSettings: Equatable {
  var precise = false
  /// Across, in screen points (Android's `eraserSize`): it covers less of the page when zoomed in.
  var size: Float = 16
  var affects = PenFilter()

  var mode: Eraser.Mode { precise ? .AREA : .STROKE }
}

struct EraserState {
  var watcher: StrokeWatcher?
  var sweep: EraserSweep?
  let cursor = CAShapeLayer()
}

/// One pass of the eraser, from landing to lifting: a single undo step.
struct EraserSweep {
  struct Ink {
    var pk: PKStroke
    var stroke: InkStroke
    var box: TaliCore.Rect
    /// Cut this sweep, so not stored yet.
    var piece = false
  }

  let before: PageState
  var last: Pt
  var ink: [Ink]
  /// Fills being rubbed out: their pictures as they are now, not yet saved (see FillEraser.swift).
  var rubbed: [String: CGContext] = [:]
  var changed = false
}

/// The eraser (Android's `startErase`, `eraseSegment`, `finishErase`). PencilKit's own knows neither
/// pen types, shapes nor fills, and what its precise eraser leaves can't be stored as the strokes it
/// came from, so the notebook erases by itself. Typed text and pictures have no pen, so it leaves
/// them alone (Android's `eraserHits`). Locked things too: locked writing isn't in PencilKit's
/// drawing at all (the page draws it).
extension NoteCanvas.Coordinator {
  private static let cursorFill = UIColor(argb: Int32(bitPattern: 0x22D1_AEFF))
  private static let cursorEdge = UIColor(argb: Int32(bitPattern: 0xAA5E_4B8B))

  func installEraser(on v: PKCanvasView) {
    let w = StrokeWatcher(target: nil, action: nil)
    w.delegate = self
    w.accepts = { [weak self] t in self.map { $0.parent.tool == .eraser && $0.draws(t) && $0.claim(t) == nil } ?? false }
    w.began = { [weak self] t, _ in self?.eraseBegan(t) }
    w.moved = { [weak self] t, e in self?.eraseMoved(e.coalescedTouches(for: t) ?? [t]) }
    w.ended = { [weak self] cancelled in self?.eraseEnded(cancelled) }
    v.addGestureRecognizer(w)
    v.panGestureRecognizer.require(toFail: w)
    erasing.watcher = w
    erasing.cursor.fillColor = Self.cursorFill.cgColor
    erasing.cursor.strokeColor = Self.cursorEdge.cgColor
    erasing.cursor.lineWidth = 1.2
    erasing.cursor.zPosition = 12
    erasing.cursor.isHidden = true
    v.layer.addSublayer(erasing.cursor)
  }

  private func eraseBegan(_ t: UITouch) {
    guard let canvas else { return }
    if canvas.drawing.strokes.count != stored.count { sync(canvas.drawing) }
    let p = worldPoint(of: t)
    erasing.sweep = EraserSweep(
      before: pageState, last: p,
      ink: zip(canvas.drawing.strokes, stored).map { EraserSweep.Ink(pk: $0, stroke: $1.stroke, box: $1.stroke.bounds) })
    erase(to: p)
    moveCursor(to: t)
  }

  private func eraseMoved(_ touches: [UITouch]) {
    for t in touches { erase(to: worldPoint(of: t)) }
    if let t = touches.last { moveCursor(to: t) }
  }

  /// The circle shows only while erasing (Android: one that followed the pen's hover looked like a mark left behind).
  private func moveCursor(to t: UITouch) {
    guard let canvas else { return }
    let r = CGFloat(parent.eraser.size) / 2
    let at = t.location(in: canvas)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    erasing.cursor.path = CGPath(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2), transform: nil)
    erasing.cursor.isHidden = false
    CATransaction.commit()
  }

  private func erase(to p: Pt) {
    guard let canvas, var sweep = erasing.sweep else { return }
    let a = sweep.last
    sweep.last = p
    let radius = parent.eraser.size / 2 / Float(canvas.zoomScale)
    let mode = parent.eraser.mode
    let affects = parent.eraser.affects
    guard let path = TaliCore.Rect.around([a, p]) else { return }

    var inkChanged = false
    var ink: [EraserSweep.Ink] = []
    ink.reserveCapacity(sweep.ink.count)
    func cut(_ stroke: InkStroke, into pieces: [InkInputs]) {
      inkChanged = true
      for inputs in pieces {
        for kept in onItsPage(inputs, of: stroke) {
          let piece = InkStroke(id: newId(), z: stroke.z, pen: stroke.pen, tags: stroke.tags, color: stroke.color, size: stroke.size, inputs: kept)
          ink.append(EraserSweep.Ink(pk: piece.pkStroke(mask: mask(for: piece)), stroke: piece, box: piece.bounds, piece: true))
        }
      }
    }
    for item in sweep.ink {
      let s = item.stroke
      guard affects.hits(s.pen), item.box.outset(radius).intersects(path) else {
        ink.append(item)
        continue
      }
      switch Eraser.hit(s.inputs, size: s.size, mode: mode, from: a, to: p, radius: radius) {
      case .missed: ink.append(item)
      case .whole: inkChanged = true
      case .pieces(let left): cut(s, into: left)
      }
    }

    var keptShapes: [ShapeRow] = []
    var shapesChanged = false
    for shape in shapes {
      let pen = PenType(rawValue: shape.pen) ?? .FINELINER
      guard !shape.locked, affects.hits(pen), let box = shape.geometry.bounds(shape.size), box.outset(radius).intersects(path) else {
        keptShapes.append(shape)
        continue
      }
      let lines = shape.strokes.map(StrokeAlong.inputs)
      let hits = lines.map { Eraser.hit($0, size: shape.size, mode: mode, from: a, to: p, radius: radius) }
      if hits.allSatisfy({ $0 == .missed }) {
        keptShapes.append(shape)
        continue
      }
      shapesChanged = true
      guard mode == .AREA else { continue }
      // What the precise eraser leaves of a shape carries on as plain ink (Android's `toInk`).
      let asInk = InkStroke(id: "", z: shape.z, pen: pen, color: shape.inkColor, size: shape.size, inputs: InkInputs(points: []))
      for (line, hit) in zip(lines, hits) {
        switch hit {
        case .missed: cut(asInk, into: [line])
        case .whole: break
        case .pieces(let left): cut(asInk, into: left)
        }
      }
    }

    let fillsChanged = eraseFills(from: a, to: p, reach: radius, rubbed: &sweep.rubbed)

    if shapesChanged { setShapes(keptShapes) }
    if inkChanged {
      sweep.ink = ink
      loading = true
      canvas.drawing = PKDrawing(strokes: ink.map(\.pk))
      loading = false
    }
    sweep.changed = sweep.changed || inkChanged || shapesChanged || fillsChanged
    erasing.sweep = sweep
  }

  /// A stroke that ran off its page is hidden past the edge; a piece of it that begins out there
  /// would count as written on the next page and show, so pieces are kept to the stroke's own page.
  private func onItsPage(_ piece: InkInputs, of stroke: InkStroke) -> [InkInputs] {
    guard let first = stroke.inputs.points.first, let page = pageClip(startingAt: first.y) else { return [piece] }
    return StrokeCut.split(piece, maxGap: 1, erased: { x, y in !page.contains(CGPoint(x: CGFloat(x), y: CGFloat(y))) }) ?? [piece]
  }

  private func eraseEnded(_ cancelled: Bool) {
    erasing.cursor.isHidden = true
    guard let canvas, let sweep = erasing.sweep else { return }
    erasing.sweep = nil
    guard sweep.changed else { return }
    if cancelled {
      // A second finger made it a pinch or a scroll: nothing is erased.
      showFills(sweep.before.fills)
      restore(sweep.before)
      return
    }
    finishFillErase(sweep.rubbed, from: sweep.before.fills)
    for item in sweep.ink where item.piece { pending[StrokeKey(item.pk)] = item.stroke }
    record(sweep.before)
    sync(canvas.drawing)
    reportUndo()
  }
}
