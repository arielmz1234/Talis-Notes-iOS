import PencilKit
import TaliCore
import UIKit

/// A dot on a side of the text box being edited, or a chip at one of its lower corners.
final class TextBoxHandle: UIView, UIGestureRecognizerDelegate {
  enum Kind: Equatable {
    /// 0 left, 1 right, 2 top, 3 bottom.
    case side(Int)
    case resize, move
  }

  let kind: Kind
  let pan = UIPanGestureRecognizer()
  var dragged: (UIGestureRecognizer.State, CGPoint) -> Void = { _, _ in }

  init(_ kind: Kind) {
    self.kind = kind
    let side: CGFloat = kind == .resize || kind == .move ? 30 : 32
    super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
    backgroundColor = .clear
    isOpaque = false
    pan.addTarget(self, action: #selector(panned))
    pan.delegate = self
    addGestureRecognizer(pan)
    isAccessibilityElement = true
    accessibilityTraits = .adjustable
    switch kind {
    case .side(let i): accessibilityIdentifier = "text-side-\(i)"
    case .resize:
      accessibilityIdentifier = "text-resize"
      accessibilityLabel = L("resize_the_text_box")
    case .move:
      accessibilityIdentifier = "text-move"
      accessibilityLabel = L("move_the_text_box")
    }
  }

  required init?(coder: NSCoder) { fatalError() }

  /// Where the finger came down: the drag is measured from there, so the box stays under the
  /// finger (a pan's own translation leaves out the first few points, before it knew it was a pan).
  private var down: CGPoint?

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    down = touches.first?.location(in: superview)
    super.touchesBegan(touches, with: event)
  }

  @objc private func panned() {
    let at = pan.location(in: superview), from = down ?? at
    dragged(pan.state, CGPoint(x: at.x - from.x, y: at.y - from.y))
  }

  /// The page doesn't scroll, and nothing is written, while one of these is dragged.
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
    other.view is UIScrollView
  }

  override func draw(_ rect: CGRect) {
    guard let cg = UIGraphicsGetCurrentContext() else { return }
    let accent = SelectionChromeView.accent
    let c = CGPoint(x: bounds.midX, y: bounds.midY)
    switch kind {
    case .side:
      let dot = CGRect(x: c.x - 6.5, y: c.y - 6.5, width: 13, height: 13)
      cg.setFillColor(UIColor.white.cgColor)
      cg.fillEllipse(in: dot)
      cg.setStrokeColor(accent.cgColor)
      cg.setLineWidth(2)
      cg.strokeEllipse(in: dot.insetBy(dx: 1, dy: 1))
    case .resize, .move:
      cg.saveGState()
      cg.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: UIColor.black.withAlphaComponent(0.2).cgColor)
      cg.setFillColor((traitCollection.userInterfaceStyle == .dark ? UIColor(argb: Int32(bitPattern: 0xFF2E_2848)) : .white).cgColor)
      cg.fillEllipse(in: bounds.insetBy(dx: 2, dy: 2))
      cg.restoreGState()
      cg.setStrokeColor(accent.cgColor)
      cg.setLineWidth(1.6)
      cg.setLineCap(.round)
      cg.setLineJoin(.round)
      let a: CGFloat = 5, h: CGFloat = 3
      if kind == .resize {
        // A double-headed arrow along the diagonal.
        cg.move(to: CGPoint(x: c.x - a, y: c.y - a))
        cg.addLine(to: CGPoint(x: c.x + a, y: c.y + a))
        for s: CGFloat in [-1, 1] {
          cg.move(to: CGPoint(x: c.x + s * (a - h), y: c.y + s * a))
          cg.addLine(to: CGPoint(x: c.x + s * a, y: c.y + s * a))
          cg.addLine(to: CGPoint(x: c.x + s * a, y: c.y + s * (a - h)))
        }
      } else {
        // A four-way arrow.
        let r: CGFloat = 7, k: CGFloat = 2.2
        cg.move(to: CGPoint(x: c.x - r, y: c.y))
        cg.addLine(to: CGPoint(x: c.x + r, y: c.y))
        cg.move(to: CGPoint(x: c.x, y: c.y - r))
        cg.addLine(to: CGPoint(x: c.x, y: c.y + r))
        for (dx, dy): (CGFloat, CGFloat) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
          let tip = CGPoint(x: c.x + dx * r, y: c.y + dy * r)
          cg.move(to: CGPoint(x: tip.x - dx * k - dy * k, y: tip.y - dy * k - dx * k))
          cg.addLine(to: tip)
          cg.addLine(to: CGPoint(x: tip.x - dx * k + dy * k, y: tip.y - dy * k + dx * k))
        }
      }
      cg.strokePath()
    }
  }
}

/// Sizing and moving the text box being edited (Android's `SideDot` and `EditorChip` in
/// `TextEditor.kt`): it acts like a rectangle. A dot in the middle of each side moves that side
/// (left and right set the width, top and bottom the height), the opposite side staying put; the
/// chip at the lower right moves that corner; the chip at the lower left carries the whole box. The
/// text keeps its size (A− / A+ change that). In world units, so it's the same at any zoom.
extension NoteCanvas.Coordinator {
  /// The box's frame stands this far off the text (Android's 6 dp), and the chips this far off its corners.
  private static let textPad: CGFloat = 6
  private static let chipGap: CGFloat = 10

  func installTextBoxHandles(on canvas: PKCanvasView, around v: UITextView) {
    let frame = textEdit.frame
    frame.fillColor = UIColor.clear.cgColor
    frame.strokeColor = SelectionChromeView.accent.withAlphaComponent(0.55).cgColor
    frame.lineWidth = 1.5
    frame.lineDashPattern = [6, 5]
    frame.zPosition = 8
    canvas.layer.addSublayer(frame)
    let kinds: [TextBoxHandle.Kind] = [.side(0), .side(1), .side(2), .side(3), .resize, .move]
    textEdit.handles = kinds.map { kind in
      let handle = TextBoxHandle(kind)
      var start: TextRow?
      var content: Float = 0
      handle.dragged = { [weak self] state, by in
        guard let self, let canvas = self.canvas else { return }
        if state == .began {
          start = self.textEdit.editing
          content = self.textBoxContent()
        }
        guard state == .began || state == .changed, let from = start else { return }
        let z = Float(max(canvas.zoomScale, 0.01))
        let d = Pt(Float(by.x) / z, Float(by.y) / z)
        switch kind {
        case .side(let i): self.textEdit.editing = from.withSide(i, draggedBy: d, content: content, text: self.textBoxTextHeight())
        case .resize: self.textEdit.editing = from.withCorner(draggedBy: d, content: content)
        case .move:
          var moved = from
          moved.x += d.x
          moved.y += d.y
          self.textEdit.editing = moved
        }
        self.layoutTextEditor()
      }
      canvas.addSubview(handle)
      canvas.drawingGestureRecognizer.require(toFail: handle.pan)
      return handle
    }
    // Picked up, not yet typing: dragging the box carries it, a tap on it brings the keyboard.
    let carry = UIPanGestureRecognizer(target: self, action: #selector(carryTextBox(_:)))
    let type = UITapGestureRecognizer(target: self, action: #selector(typeInTextBox))
    carry.delegate = self
    type.delegate = self
    v.addGestureRecognizer(carry)
    v.addGestureRecognizer(type)
    canvas.drawingGestureRecognizer.require(toFail: carry)
    canvas.panGestureRecognizer.require(toFail: carry)
  }

  func removeTextBoxHandles() {
    textEdit.handles.forEach { $0.removeFromSuperview() }
    textEdit.handles = []
    textEdit.frame.removeFromSuperlayer()
  }

  /// How tall the typed text is, and how tall the box is now (what she set, or the text's own if
  /// that's taller), in world units.
  private func textBoxTextHeight() -> Float {
    guard let canvas, let v = textEdit.view else { return 0 }
    return Float(v.sizeThatFits(CGSize(width: v.frame.width, height: .greatestFiniteMagnitude)).height / max(canvas.zoomScale, 0.01))
  }

  private func textBoxContent() -> Float {
    guard let t = textEdit.editing else { return 0 }
    return max(t.height, textBoxTextHeight(), t.fontSize * TextRow.line)
  }

  func layoutTextBoxHandles(around text: CGRect) {
    let box = text.insetBy(dx: -Self.textPad, dy: -Self.textPad)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    textEdit.frame.path = UIBezierPath(roundedRect: box, cornerRadius: 8).cgPath
    CATransaction.commit()
    for handle in textEdit.handles {
      switch handle.kind {
      case .side(0): handle.center = CGPoint(x: box.minX, y: box.midY)
      case .side(1): handle.center = CGPoint(x: box.maxX, y: box.midY)
      case .side(2): handle.center = CGPoint(x: box.midX, y: box.minY)
      case .side: handle.center = CGPoint(x: box.midX, y: box.maxY)
      case .resize: handle.center = CGPoint(x: box.maxX + Self.chipGap, y: box.maxY + Self.chipGap)
      case .move: handle.center = CGPoint(x: box.minX - Self.chipGap, y: box.maxY + Self.chipGap)
      }
    }
  }

  @objc func typeInTextBox() {
    guard let v = textEdit.view, !textEdit.typing else { return }
    textEdit.typing = true
    v.isEditable = true
    v.isSelectable = true
    v.becomeFirstResponder()
  }

  @objc func carryTextBox(_ g: UIPanGestureRecognizer) {
    guard let canvas, !textEdit.typing, var t = textEdit.editing else { return }
    let by = g.translation(in: canvas)
    g.setTranslation(.zero, in: canvas)
    let z = Float(max(canvas.zoomScale, 0.01))
    t.x += Float(by.x) / z
    t.y += Float(by.y) / z
    textEdit.editing = t
    layoutTextEditor()
  }
}
