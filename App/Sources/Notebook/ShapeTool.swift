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
    clearSelection()
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
    let pen = shapePen
    shapeTool.preview = ShapeRow(geometry: parent.shapeKind.drawn(start, p), pen: pen.type == .HIGHLIGHTER ? "FINELINER" : pen.type.rawValue, color: pen.color | Int32(bitPattern: 0xFF00_0000), size: pen.type == .HIGHLIGHTER ? 2.5 : pen.size)
    drawShapePreview()
  }

  private func shapeEnded(_ cancelled: Bool) {
    let shape = shapeTool.drawing && !cancelled ? shapeTool.preview : nil
    shapeTool.start = nil
    shapeTool.drawing = false
    shapeTool.preview = nil
    drawShapePreview()
    if let shape { addShape(shape) }
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
  }
}
