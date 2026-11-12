import PencilKit
import TaliCore
import UIKit

/// The Shapes tool (Android's `Tool.SHAPE`, `buildShape`): the pen (or a finger where fingers draw)
/// drags out the chosen shape, shown live, kept on lift and picked up at once. A tap draws nothing:
/// only a slide of `startSlide` (Android's `SHAPE_START_DP`); a tap on a shape picks it up. Shapes
/// take the look of the pen last used.
struct ShapeToolState {
  var watcher: StrokeWatcher?
  var start: Pt?
  var startScreen: CGPoint = .zero
  var drawing = false
  var preview: ShapeRow?
  let layer = CAShapeLayer()
  /// The dotted line across a rectangle that's exactly square, or an ellipse that's exactly round.
  let squareHint = CAShapeLayer()
}

extension NoteCanvas.Coordinator {
  static let shapeStartSlide: CGFloat = 12

  func installShapeTool(on v: PKCanvasView) {
    let w = StrokeWatcher(target: nil, action: nil)
    w.delegate = self
    w.isEnabled = false
    w.accepts = { [weak self] t in self.map { $0.parent.tool == .shape && $0.draws(t) && $0.claim(t) == nil } ?? false }
    w.began = { [weak self] t, _ in self?.shapeBegan(t) }
    w.moved = { [weak self] t, _ in self?.shapeMoved(t) }
    w.ended = { [weak self] cancelled in self?.shapeEnded(cancelled) }
    v.addGestureRecognizer(w)
    // One finger or the pen draws the shape; scrolling waits until it's clear it isn't one.
    v.panGestureRecognizer.require(toFail: w)
    shapeTool.watcher = w
    shapeTool.layer.fillColor = UIColor.clear.cgColor
    shapeTool.layer.lineCap = .round
    shapeTool.layer.lineJoin = .round
    shapeTool.layer.zPosition = 9
    v.layer.addSublayer(shapeTool.layer)
    shapeTool.squareHint.strokeColor = UIColor(argb: Int32(bitPattern: 0xC87A_4ED6)).cgColor
    shapeTool.squareHint.lineWidth = 2.4
    shapeTool.squareHint.lineCap = .round
    shapeTool.squareHint.lineDashPattern = [0.1, 6]
    shapeTool.squareHint.zPosition = 9
    v.layer.addSublayer(shapeTool.squareHint)
  }

  /// The pen last used (a new text box takes its colour).
  var shapePen: PenSlot {
    parent.pens.first { $0.id == lastPenId } ?? parent.pens.first ?? PenSlot.defaults[0]
  }

  /// How shapes are drawn (Android's `shapeLook`): the tool's own style, or like the pen last used.
  var shapeLook: ShapeLook { ShapeSettings.look(active: parent.pens.first { $0.id == lastPenId }, pens: parent.pens) }

  private func shapeBegan(_ t: UITouch) {
    guard let canvas else { return }
    let q = t.location(in: canvas)
    shapeTool.startScreen = q
    shapeTool.start = Pt(Float(q.x / canvas.zoomScale), Float(q.y / canvas.zoomScale))
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
    let p = Pt(Float(q.x / canvas.zoomScale), Float(q.y / canvas.zoomScale))
    shapeTool.preview = shapeLook.row(parent.shape.drawn(start, p))
    drawShapePreview()
  }

  private func shapeEnded(_ cancelled: Bool) {
    let shape = shapeTool.drawing && !cancelled ? shapeTool.preview : nil
    let tapped = shapeTool.drawing || cancelled ? nil : shapeTool.start
    shapeTool.start = nil
    shapeTool.drawing = false
    shapeTool.preview = nil
    drawShapePreview()
    if let shape {
      selectShape(addShape(shape), soft: true)
    } else if let tapped, case let .shape(under)? = item(at: tapped) {
      selectShape(under)
    }
  }

  private func drawShapePreview() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    guard let canvas, let s = shapeTool.preview else {
      shapeTool.layer.path = nil
      shapeTool.squareHint.path = nil
      return
    }
    let z = canvas.zoomScale
    let hint = CGMutablePath()
    if let (a, b) = s.geometry.squareHint { hint.addLines(between: [a, b].map { CGPoint(x: CGFloat($0.x) * z, y: CGFloat($0.y) * z) }) }
    shapeTool.squareHint.path = hint
    let path = CGMutablePath()
    for line in s.strokes where line.count > 1 {
      path.addLines(between: line.map { CGPoint(x: CGFloat($0.x) * z, y: CGFloat($0.y) * z) })
    }
    shapeTool.layer.path = path
    shapeTool.layer.strokeColor = UIColor(argb: s.inkColor).cgColor
    shapeTool.layer.lineWidth = CGFloat(s.size) * z
    shapeTool.layer.fillColor = (s.geometry.closed ? s.fill.map { UIColor(argb: $0).cgColor } : nil) ?? UIColor.clear.cgColor
  }
}
