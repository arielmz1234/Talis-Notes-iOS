import PencilKit
import TaliCore
import UIKit

/// Typed text (Android's `TextItem`, `startText`, `finishText`, `ui/notebook/TextEditor.kt`): the
/// keyboard button opens a new box where typing would go on a page (at the left margin, just below
/// what's already written, as wide as the page between its margins); a finger tap on a box opens it to
/// type in; a tap anywhere else finishes it. Boxes are stored as Android stores them and drawn by the
/// page layer as real text.
struct TextEditState {
  var view: UITextView?
  /// The box being edited (its place, width and size), and how it was before (nil for a new one).
  var editing: TextRow?
  var original: TextRow?
  var tap: UITapGestureRecognizer?
  /// A− / A+ above the box (Android's editor `SizeButton`s).
  var sizeBar: UIView?
}

extension NoteCanvas.Coordinator: UITextViewDelegate {
  var texts: [TextRow] { pages?.pages.under.texts ?? [] }

  func installTextBoxes(on v: PKCanvasView) {
    let tap = UITapGestureRecognizer(target: self, action: #selector(textTap(_:)))
    tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    tap.cancelsTouchesInView = false
    tap.delegate = self
    v.addGestureRecognizer(tap)
    textEdit.tap = tap
  }

  @objc func textTap(_ g: UITapGestureRecognizer) {
    guard let canvas else { return }
    if textEdit.view != nil {
      finishText()
      return
    }
    guard !parent.viewOnly, parent.tool != .lasso, parent.tool != .fill else { return }
    let q = g.location(in: canvas)
    let p = CGPoint(x: q.x / canvas.zoomScale, y: q.y / canvas.zoomScale)
    if let t = texts.last(where: { !$0.locked && TextLook.frame($0).insetBy(dx: -6, dy: -6).contains(p) }) { editText(t) }
  }

  /// A new box where typing would go (Android's `startText`).
  func startNewText() {
    guard let canvas else { return }
    finishText()
    clearSelection()
    let mm: Float = 160 / 25.4
    let z = Float(max(canvas.zoomScale, 0.01))
    let pen = shapePen
    let color = pen.color | Int32(bitPattern: 0xFF00_0000)
    var t: TextRow
    if paged {
      let midY = Float((canvas.contentOffset.y + canvas.bounds.height / 2) / CGFloat(z))
      let r = layout.rect(min(max(layout.indexAt(midY), 0), pageCount - 1))
      var bottoms = stored.compactMap { s -> Float? in
        let b = s.stroke.bounds
        return b.center.y > r.top && b.center.y < r.bottom ? b.bottom : nil
      }
      bottoms += shapes.compactMap { s -> Float? in
        guard let b = s.geometry.bounds(s.size), b.center.y > r.top, b.center.y < r.bottom else { return nil }
        return b.bottom
      }
      bottoms += texts.compactMap { t -> Float? in
        let b = TextLook.frame(t)
        return Float(b.midY) > r.top && Float(b.midY) < r.bottom ? Float(b.maxY) : nil
      }
      let top = min(bottoms.max().map { $0 + 6 * mm } ?? (r.top + 22 * mm), r.bottom - 30 * mm)
      t = TextRow(text: "", x: r.left + 20 * mm, y: top, width: r.width - 40 * mm, fontSize: TextRow.defaultSize, color: color)
    } else {
      let left = Float((canvas.contentOffset.x + 48) / CGFloat(z))
      let top = Float((canvas.contentOffset.y + parent.topClearance + 32) / CGFloat(z))
      t = TextRow(text: "", x: left, y: top, width: min(Float(canvas.bounds.width) / z * 0.7, 1100), fontSize: TextRow.defaultSize, color: color)
    }
    t.id = newId()
    textEdit.original = nil
    beginEditing(t)
  }

  /// Opens an existing box to type in.
  func editText(_ t: TextRow) {
    textEdit.original = t
    // It's drawn by the editor meanwhile, not by the page.
    pages?.pages.under.texts.removeAll { $0.id == t.id }
    pages?.layer.setNeedsDisplay()
    beginEditing(t)
  }

  private func beginEditing(_ t: TextRow) {
    guard let canvas else { return }
    textEdit.editing = t
    let v = UITextView()
    v.backgroundColor = .clear
    v.textContainerInset = .zero
    v.textContainer.lineFragmentPadding = 0
    v.isScrollEnabled = false
    v.delegate = self
    v.layer.borderColor = UIColor(argb: Int32(bitPattern: 0x667A_4ED6)).cgColor
    v.layer.borderWidth = 1
    v.layer.cornerRadius = 4
    v.accessibilityIdentifier = "text-editor"
    canvas.addSubview(v)
    textEdit.view = v
    textEdit.sizeBar = makeSizeBar()
    if let bar = textEdit.sizeBar { canvas.addSubview(bar) }
    (canvas as? NoteCanvasView)?.typing = [v, textEdit.sizeBar].compactMap { $0 }
    layoutTextEditor()
    v.attributedText = NSAttributedString(string: t.text, attributes: editorAttributes(t))
    TextLook.setDirections(v.textStorage)
    v.becomeFirstResponder()
    // Comfortably below the toolbars and above the keyboard (Android's `showForTyping`).
    let clearance = parent.topClearance
    let want = v.frame.minY - (clearance + 56)
    if v.frame.minY < canvas.contentOffset.y + clearance + 36 || v.frame.minY > canvas.contentOffset.y + canvas.bounds.height * 0.4 {
      canvas.setContentOffset(CGPoint(x: canvas.contentOffset.x, y: want), animated: true)
    }
    // Once it's on screen: a text view added and focused in the same moment can miss the keyboard.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak v] in
      if let v, v.superview != nil, !v.isFirstResponder { v.becomeFirstResponder() }
    }
  }

  private func editorAttributes(_ t: TextRow) -> [NSAttributedString.Key: Any] {
    TextLook.attributes(size: CGFloat(t.fontSize) * (canvas?.zoomScale ?? 1), color: t.color)
  }

  /// Keeps the editor over its box as the zoom changes.
  func layoutTextEditor() {
    guard let canvas, let v = textEdit.view, let t = textEdit.editing else { return }
    let z = canvas.zoomScale
    let w = CGFloat(t.width) * z
    let fit = v.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
    let h = max(fit, CGFloat(max(t.fontSize * TextRow.line, t.height)) * z)
    v.frame = CGRect(x: CGFloat(t.x) * z, y: CGFloat(t.y) * z, width: w, height: h)
    if let bar = textEdit.sizeBar { bar.frame.origin = CGPoint(x: v.frame.maxX - bar.frame.width, y: v.frame.minY - bar.frame.height - 6) }
    let attrs = editorAttributes(t)
    v.typingAttributes = attrs
    if let text = v.attributedText, text.length > 0, (text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize != (attrs[.font] as? UIFont)?.pointSize {
      v.attributedText = NSAttributedString(string: text.string, attributes: attrs)
      TextLook.setDirections(v.textStorage)
    }
  }

  func textViewDidChange(_ textView: UITextView) {
    if textView.markedTextRange == nil { TextLook.setDirections(textView.textStorage) }
    layoutTextEditor()
  }

  private func makeSizeBar() -> UIView {
    let bar = UIStackView()
    bar.axis = .horizontal
    bar.spacing = 2
    bar.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
    bar.layer.cornerRadius = 12
    bar.layer.borderColor = UIColor(argb: Int32(bitPattern: 0x337A_4ED6)).cgColor
    bar.layer.borderWidth = 1
    bar.isLayoutMarginsRelativeArrangement = true
    bar.layoutMargins = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
    for (title, grow) in [("A−", false), ("A+", true)] {
      let b = UIButton(type: .system)
      b.setTitle(title, for: .normal)
      b.titleLabel?.font = .systemFont(ofSize: grow ? 17 : 14, weight: .semibold)
      b.tintColor = UIColor(argb: Int32(bitPattern: 0xFF7A_4ED6))
      b.accessibilityIdentifier = grow ? "text-bigger" : "text-smaller"
      b.addAction(UIAction { [weak self] _ in self?.resizeText(grow) }, for: .touchUpInside)
      b.widthAnchor.constraint(equalToConstant: 40).isActive = true
      bar.addArrangedSubview(b)
    }
    bar.frame.size = bar.systemLayoutSizeFitting(CGSize(width: 200, height: 36))
    return bar
  }

  /// A− / A+: the text 15% smaller or bigger, between 10 and 160 (Android's limits).
  private func resizeText(_ grow: Bool) {
    guard var t = textEdit.editing, let v = textEdit.view else { return }
    t.fontSize = min(max(grow ? t.fontSize * 1.15 : t.fontSize / 1.15, 10), 160)
    textEdit.editing = t
    v.attributedText = NSAttributedString(string: v.text, attributes: editorAttributes(t))
    TextLook.setDirections(v.textStorage)
    layoutTextEditor()
  }

  /// Keeps what was typed: a new box with text is added, an emptied one removed, a changed one
  /// replaced; one undo step.
  func finishText() {
    guard let v = textEdit.view, var t = textEdit.editing else { return }
    textEdit.view = nil
    textEdit.editing = nil
    v.resignFirstResponder()
    v.removeFromSuperview()
    textEdit.sizeBar?.removeFromSuperview()
    textEdit.sizeBar = nil
    (canvas as? NoteCanvasView)?.typing = []
    let text = v.text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    t.text = text
    let original = textEdit.original
    textEdit.original = nil
    var before = texts
    if let original { before.append(original) }
    var after = texts
    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      if t.z == 0 { t.z = max(stored.map(\.stroke.z).max() ?? 0, shapeZ) + 1 }
      after.append(t)
    }
    // The original was only off the page while editing: put the list back as it was before saving.
    pages?.pages.under.texts = before
    if before != after {
      setTexts(after)
      registerTextsChange(from: before, to: after)
    } else {
      pages?.layer.setNeedsDisplay()
    }
  }

  /// Makes [new] the notebook's text boxes: what changed is saved, what's gone is removed.
  func setTexts(_ new: [TextRow]) {
    guard let pages else { return }
    let old = pages.pages.under.texts
    let keep = Set(new.map(\.id))
    var before: [String: TextRow] = [:]
    for t in old { before[t.id] = t }
    do {
      for t in old where !keep.contains(t.id) { try parent.db.removeItem(t.id) }
      for t in new where before[t.id] != t { try parent.db.put(t.row(textHeight: TextLook.textHeight(t)), in: parent.notebook.id) }
    } catch {
      CrashNote.log("saving text: \(error)")
    }
    pages.pages.under.texts = new
    pages.layer.setNeedsDisplay()
    touch()
  }

  func registerTextsChange(from before: [TextRow], to after: [TextRow]) {
    canvas?.undoManager?.registerUndo(withTarget: self) { c in
      MainActor.assumeIsolated {
        c.finishText()
        c.setTexts(before)
        c.registerTextsChange(from: after, to: before)
        c.reportUndo()
      }
    }
    reportUndo()
  }
}
