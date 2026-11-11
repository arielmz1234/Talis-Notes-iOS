import ImageIO
import PDFKit
import PencilKit
import SwiftUI
import TaliCore
import UIKit

/// The tool in use (the parts ported so far).
enum Tool: Equatable {
  case pen(String)  // a PenSlot id
  case eraser
  case lasso
  case shape
}

/// What the page layer draws besides paper: shapes and pictures from the notebook (pictures first,
/// then shapes, all under the writing for now).
struct UnderItems: @unchecked Sendable {
  var shapes: [ShapeRow] = []
  var pictures: [PlacedPicture] = []
  /// Pages of an imported PDF, drawn from the PDF itself (sharp at any zoom) instead of their pictures.
  var pdfPages: [(id: String, rect: CGRect, page: SharpPage)] = []
  /// Typed text boxes (drawn as real text, sharp at any zoom).
  var texts: [TextRow] = []
}

/// Paper, pictures and shapes for the page column, drawn in tiles off the main thread so they stay
/// sharp at any zoom. Everything it reads is set from the main thread before it's asked to draw.
final class PagesLayer: CATiledLayer, @unchecked Sendable {
  nonisolated(unsafe) var layout = Pages.portrait
  nonisolated(unsafe) var count = 1
  nonisolated(unsafe) var paper = PaperStyle.GRID
  nonisolated(unsafe) var dark = false
  nonisolated(unsafe) var under = UnderItems()
  /// Off when the paper is already painted (a PDF export painting it over a whole long page).
  nonisolated(unsafe) var drawsPaper = true

  override class func fadeDuration() -> CFTimeInterval { 0.08 }

  var worldSize: CGSize { CGSize(width: CGFloat(layout.width), height: CGFloat(layout.rect(max(count, 1) - 1).bottom)) }

  override func draw(in cg: CGContext) {
    let rect = cg.boundingBoxOfClipPath
    let scale = max(cg.ctm.a / max(contentsScale, 1), 0.01)
    for i in 0..<max(count, 1) where drawsPaper {
      let page = CGRect(layout.rect(i))
      guard page.intersects(rect) else { continue }
      PaperPainter.draw(paper, page: page, in: cg, scale: scale, dark: dark)
    }
    for p in under.pdfPages where p.rect.intersects(rect) { p.page.draw(in: p.rect, cg) }
    for pic in under.pictures where pic.rect.intersects(rect) {
      cg.saveGState()
      cg.translateBy(x: pic.rect.minX, y: pic.rect.maxY)
      cg.scaleBy(x: 1, y: -1)
      cg.interpolationQuality = .high
      cg.draw(pic.image, in: CGRect(origin: .zero, size: pic.rect.size))
      cg.restoreGState()
    }
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    for s in under.shapes {
      let paths = s.geometry.paths(s.size)
      let path = CGMutablePath()
      for line in paths where line.count > 1 {
        path.move(to: CGPoint(x: CGFloat(line[0].x), y: CGFloat(line[0].y)))
        for p in line.dropFirst() { path.addLine(to: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))) }
      }
      guard path.boundingBox.insetBy(dx: -CGFloat(s.size) * 2, dy: -CGFloat(s.size) * 2).intersects(rect) else { continue }
      if let fill = s.fill, s.geometry.closed, let outline = paths.first, outline.count > 2 {
        let f = CGMutablePath()
        f.addLines(between: outline.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
        f.closeSubpath()
        cg.addPath(f)
        cg.setFillColor(UIColor(argb: fill).cgColor)
        cg.fillPath()
      }
      cg.addPath(path)
      cg.setStrokeColor(UIColor(argb: dark ? s.color : s.color).cgColor)
      cg.setLineWidth(CGFloat(s.size))
      if let dash = LineDash.pattern(s.line, width: CGFloat(s.size)) { cg.setLineDash(phase: 0, lengths: dash) } else { cg.setLineDash(phase: 0, lengths: []) }
      cg.strokePath()
    }
    cg.setLineDash(phase: 0, lengths: [])
    if !under.texts.isEmpty {
      UIGraphicsPushContext(cg)
      for t in under.texts {
        let box = TextLook.frame(t)
        guard box.intersects(rect) else { continue }
        TextLook.attributed(t).draw(with: CGRect(x: box.minX, y: box.minY, width: box.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
      }
      UIGraphicsPopContext()
    }
  }
}

/// How a text box looks (Android's `TextItem.layoutFor`): the sans-serif system font at its size, lines
/// 1.3 times the size apart, each paragraph running the way its first letters do (Hebrew from the right).
enum TextLook {
  static func attributed(_ t: TextRow) -> NSAttributedString {
    let s = NSMutableAttributedString(string: t.text, attributes: attributes(size: CGFloat(t.fontSize), color: t.color))
    setDirections(s)
    return s
  }

  static func attributes(size: CGFloat, color: Int32) -> [NSAttributedString.Key: Any] {
    [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor(argb: color), .paragraphStyle: paragraph(size: size, rightToLeft: false)]
  }

  /// Each paragraph runs the way its first letters do (Android's FIRSTSTRONG_LTR), not the way the
  /// app's language does: English stays on the left in Hebrew, Hebrew on the right in English.
  static func setDirections(_ s: NSMutableAttributedString) {
    let text = s.string
    guard let size = (s.length > 0 ? s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont : nil)?.pointSize else { return }
    for p in TextDirection.paragraphs(text) {
      let r = NSRange(p.range.lowerBound..<(p.range.upperBound < text.endIndex ? text.index(after: p.range.upperBound) : p.range.upperBound), in: text)
      s.addAttribute(.paragraphStyle, value: paragraph(size: size, rightToLeft: p.rightToLeft), range: r)
    }
  }

  private static func paragraph(size: CGFloat, rightToLeft: Bool) -> NSParagraphStyle {
    let p = NSMutableParagraphStyle()
    p.minimumLineHeight = size * CGFloat(TextRow.line)
    p.maximumLineHeight = size * CGFloat(TextRow.line)
    p.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
    p.alignment = rightToLeft ? .right : .left
    return p
  }

  /// How tall the laid-out text is in world units.
  static func textHeight(_ t: TextRow) -> Float {
    Float(ceil(attributed(t).boundingRect(with: CGSize(width: CGFloat(t.width), height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil).height))
  }

  /// The box it fills: its width, and the taller of the text, a line and its own height.
  static func frame(_ t: TextRow) -> CGRect {
    let h = max(textHeight(t), t.fontSize * TextRow.line, t.height)
    return CGRect(x: CGFloat(t.x), y: CGFloat(t.y), width: CGFloat(t.width), height: CGFloat(h))
  }
}

/// Android's line styles as Core Graphics dashes (visible lengths in multiples of the line's width; 0 = a round dot).
enum LineDash {
  static func pattern(_ name: String, width: CGFloat) -> [CGFloat]? {
    let p: [CGFloat]
    switch name {
    case "DOTTED": p = [0, 1.7]
    case "LONG_DASH": p = [6, 2.4]
    case "SHORT_DASH": p = [2.4, 2]
    case "DOT_DASH": p = [4, 2, 0, 2]
    case "MIXED_DASH": p = [6, 2, 2.2, 2]
    default: return nil
    }
    // With round caps each part grows by a width, so the gaps take that back.
    return p.enumerated().map { i, v in i % 2 == 0 ? max(v * width, 0.01) : (v + 1) * width }
  }
}

/// PencilKit's canvas, telling the notebook when its size changes (so the page is fitted as soon as
/// it has one) and showing VoiceOver the text box being typed in, which PencilKit hides like all of its
/// subviews.
final class NoteCanvasView: PKCanvasView {
  /// The canvas got a new size (it appeared, the notebook slid in, the device turned).
  var onResize: () -> Void = {}
  private var laidOutSize: CGSize = .zero

  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.size != laidOutSize {
      laidOutSize = bounds.size
      onResize()
    }
  }

  var typing: [UIView] = [] {
    didSet { UIAccessibility.post(notification: .layoutChanged, argument: typing.first) }
  }

  override var accessibilityElements: [Any]? {
    get { typing.isEmpty ? super.accessibilityElements : typing }
    set { super.accessibilityElements = newValue }
  }

  override var isAccessibilityElement: Bool {
    get { typing.isEmpty && super.isAccessibilityElement }
    set { super.isAccessibilityElement = newValue }
  }
}

/// The page column under the writing.
final class PagesView: UIView {
  override class var layerClass: AnyClass { PagesLayer.self }
  var pages: PagesLayer { layer as! PagesLayer }

  override init(frame: CGRect) {
    super.init(frame: frame)
    pages.levelsOfDetail = 6
    pages.levelsOfDetailBias = 4
    pages.tileSize = CGSize(width: 512, height: 512)
    isOpaque = false
    backgroundColor = .clear
    isUserInteractionEnabled = false
  }

  required init?(coder: NSCoder) { fatalError() }

  var worldSize: CGSize { pages.worldSize }
}

/// The notebook's canvas: PencilKit draws the live stroke with Apple Pencil's low latency, and every
/// finished stroke is stored the Android way (`InkCodec`) so backups move between platforms. The
/// drawing is kept in world units (zoom 1 = 100%); pages sit underneath.
struct NoteCanvas: UIViewRepresentable {
  let notebook: NotebookMeta
  let db: NotesDb
  var tool: Tool
  var pens: [PenSlot]
  var viewOnly = false
  /// How far down the toolbars reach over the canvas (Android's `topClearance`: two rows when narrow).
  var topClearance: CGFloat = 104
  var settings: CanvasSettings
  /// Lets the notebook screen ask for page pictures.
  var bridge: CanvasBridge? = nil
  var eraser = EraserSettings()
  /// The shape the Shapes tool draws.
  var shapeKind: ShapeKind = .RECTANGLE
  var onUndoState: (Bool, Bool) -> Void
  var onPageCount: (Int) -> Void
  /// Where what the lasso picked up is on screen (window coordinates), or nil; for the selection menu.
  var onSelection: (CGRect?) -> Void = { _ in }
  /// A short message at the bottom ("Copied — hold anywhere to paste it").
  var onHint: (String) -> Void = { _ in }
  /// A hold on the page offering Paste there (window coordinates), or nil.
  var onPasteOffer: (CGPoint?) -> Void = { _ in }
  /// The page in the middle of the screen and the zoom, as they change (for the page and zoom chips).
  var onView: (Int, CGFloat) -> Void = { _, _ in }
  @Binding var command: CanvasCommand?

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> PKCanvasView {
    let c = context.coordinator
    let v = NoteCanvasView()
    v.delegate = c
    v.drawingPolicy = .pencilOnly
    if ProcessInfo.processInfo.arguments.contains("-uitest") { v.drawingPolicy = .anyInput }
    v.backgroundColor = .clear
    v.isOpaque = false
    // PencilKit lightens dark ink in dark mode; the page is white unless the notebook has dark paper,
    // so the canvas keeps the paper's own style (ink stays as written, as on Android).
    v.overrideUserInterfaceStyle = settings.dark ? .dark : .light
    // Tap 2 fingers to undo, 3 to redo (Android's smart undo), when it's on.
    for n in [2, 3] {
      let tap = UITapGestureRecognizer(target: c, action: n == 2 ? #selector(Coordinator.twoFingerTap) : #selector(Coordinator.threeFingerTap))
      tap.numberOfTouchesRequired = n
      tap.cancelsTouchesInView = false
      v.addGestureRecognizer(tap)
    }
    c.applied = settings
    c.installSelection(on: v)
    c.installHoldToShape(on: v)
    c.installShapeEraser(on: v)
    c.installShapeTool(on: v)
    c.installTextBoxes(on: v)
    bridge?.coordinator = c
    v.minimumZoomScale = 0.2
    v.maximumZoomScale = 6
    v.showsVerticalScrollIndicator = false
    v.showsHorizontalScrollIndicator = false
    v.contentInsetAdjustmentBehavior = .never
    v.alwaysBounceVertical = true
    let pages = PagesView(frame: .zero)
    pages.pages.layout = notebook.pageLayout
    pages.pages.paper = settings.paper
    pages.pages.dark = settings.dark
    v.insertSubview(pages, at: 0)
    c.canvas = v
    c.pages = pages
    v.onResize = { [weak c] in c?.updateContent() }
    c.load()
    return v
  }

  func updateUIView(_ v: PKCanvasView, context: Context) {
    let c = context.coordinator
    c.parent = self
    c.applySettings()
    c.applyTool()
    if let cmd = command {
      DispatchQueue.main.async {
        c.run(cmd)
        command = nil
      }
    }
  }

  static func dismantleUIView(_ v: PKCanvasView, coordinator: Coordinator) {
    coordinator.saveNow()
  }

  @MainActor
  final class Coordinator: NSObject, PKCanvasViewDelegate {
    var parent: NoteCanvas
    weak var canvas: PKCanvasView?
    weak var pages: PagesView?
    /// What's stored, in drawing order, with the key that recognises each stroke in the PKDrawing.
    var stored: [(key: StrokeKey, stroke: InkStroke)] = []
    var pageCount = 1
    /// The highest z among shapes, so new items go on top of them.
    var shapeZ: Int64 = 0
    var loading = false
    private var didFit = false
    private var saveWork: DispatchWorkItem?

    init(_ parent: NoteCanvas) {
      self.parent = parent
      pageCount = max(parent.notebook.pages ?? 1, 1)
    }

    /// Recognises a PencilKit stroke across changes: its untransformed path, so a lasso move
    /// (which only changes the transform) keeps the same item.
    struct StrokeKey: Hashable {
      let created: TimeInterval
      let count: Int
      let first: CGPoint
      let last: CGPoint
      let color: Int32

      init(_ s: PKStroke) {
        created = s.path.creationDate.timeIntervalSinceReferenceDate
        count = s.path.count
        first = s.path.first?.location ?? .zero
        last = s.path.last?.location ?? .zero
        color = s.ink.color.argb
      }

      static func == (a: StrokeKey, b: StrokeKey) -> Bool {
        a.created == b.created && a.count == b.count && a.first == b.first && a.last == b.last && a.color == b.color
      }
      func hash(into h: inout Hasher) {
        h.combine(created)
        h.combine(count)
        h.combine(first.x)
        h.combine(first.y)
      }
    }

    var layout: Pages { parent.notebook.pageLayout }
    var paged: Bool { parent.notebook.pages != nil }

    /// The page a stroke belongs to (where it began), as a PencilKit mask.
    func mask(for s: InkStroke) -> UIBezierPath? {
      guard paged, let first = s.inputs.points.first else { return nil }
      guard let r = layout.clip(anchorY: first.y, count: pageCount, between: parent.settings.between) else { return nil }
      return UIBezierPath(rect: CGRect(x: CGFloat(r.left), y: CGFloat(r.top), width: CGFloat(r.width), height: CGFloat(r.height)))
    }

    func load() {
      guard let canvas else { return }
      loading = true
      let rows = (try? parent.db.items(of: parent.notebook.id)) ?? []
      var strokes: [PKStroke] = []
      stored = []
      shapeZ = 0
      var under = UnderItems()
      for row in rows {
        if let text = TextRow(row) {
          under.texts.append(text)
          continue
        }
        if let shape = ShapeRow(row) {
          under.shapes.append(shape)
          shapeZ = max(shapeZ, row.z)
          continue
        }
        if row.kind == 2, let sharp = SharpPage.of(row) {
          under.pdfPages.append(sharp)
          continue
        }
        if row.kind == 2, let pic = picture(from: row) {
          under.pictures.append(pic)
          continue
        }
        guard let ink = InkStroke(row: row) else { continue }
        let pk = ink.pkStroke(mask: mask(for: ink))
        strokes.append(pk)
        stored.append((StrokeKey(pk), ink))
      }
      pages?.pages.under = under
      canvas.drawing = PKDrawing(strokes: strokes)
      loading = false
      updateContent()
      applyTool()
      reportUndo()
    }

    /// Strokes added by the app itself (duplicate, paste, a box), waiting to be stored with their own pen.
    var pending: [StrokeKey: InkStroke] = [:]
    /// Strokes that were in the drawing at some point this session, by their key.
    var archive: [StrokeKey: InkStroke] = [:]
    /// The lasso and what it picked up (see Selection.swift).
    var lasso = LassoState()
    /// Hold-to-shape (see HoldToShape.swift).
    var hold = HoldState()
    /// The eraser on shapes (see ShapeSelection.swift).
    var shapeEraser = ShapeEraser()
    /// The Shapes tool (see ShapeTool.swift), and the pen last used (shapes take its look).
    var shapeTool = ShapeToolState()
    /// Typing in a text box (see TextBoxes.swift).
    var textEdit = TextEditState()
    var lastTool: Tool?
    var lastPenId: String?

    /// The settings the canvas was last given, to change only what changed.
    var applied: CanvasSettings?

    func applySettings() {
      guard let canvas, let pages, applied != parent.settings else { return }
      let old = applied
      applied = parent.settings
      let s = parent.settings
      if old?.paper != s.paper || old?.dark != s.dark {
        pages.pages.paper = s.paper
        pages.pages.dark = s.dark
        pages.layer.setNeedsDisplay()
        canvas.overrideUserInterfaceStyle = s.dark ? .dark : .light
      }
      if old?.between != s.between, old != nil {
        // Strokes are hidden past their page or the page column: their masks change.
        saveNow()
        load()
      }
    }

    @objc func twoFingerTap() {
      guard parent.settings.smartUndo, !parent.viewOnly else { return }
      canvas?.undoManager?.undo()
      reportUndo()
    }

    @objc func threeFingerTap() {
      guard parent.settings.smartUndo, !parent.viewOnly else { return }
      canvas?.undoManager?.redo()
      reportUndo()
    }

    func applyTool() {
      guard let canvas else { return }
      // Choosing another tool puts down the text box being typed in.
      if let last = lastTool, last != parent.tool, textEdit.view != nil {
        DispatchQueue.main.async { self.finishText() }
      }
      lastTool = parent.tool
      // Draw with finger: Auto follows iOS's own Apple Pencil setting.
      if !ProcessInfo.processInfo.arguments.contains("-uitest") {
        switch parent.settings.fingerDraws {
        case nil: canvas.drawingPolicy = .default
        case true?: canvas.drawingPolicy = .anyInput
        case false?: canvas.drawingPolicy = .pencilOnly
        }
      }
      // Just looking: fingers and the pencil scroll and zoom, nothing writes. The lasso draws its own loop.
      canvas.drawingGestureRecognizer.isEnabled = !parent.viewOnly && parent.tool != .lasso && parent.tool != .shape
      lasso.pan?.isEnabled = !parent.viewOnly && parent.tool == .lasso
      shapeTool.watcher?.isEnabled = !parent.viewOnly && parent.tool == .shape
      // Another tool puts down what the lasso picked up (after this update: it changes the screen's state).
      if parent.tool != .lasso, lasso.bounds != nil || !lasso.loop.isEmpty {
        DispatchQueue.main.async { self.clearSelection() }
      }
      switch parent.tool {
      case .pen(let id):
        lastPenId = id
        let pen = parent.pens.first { $0.id == id } ?? PenSlot.defaults[0]
        canvas.tool = PKInkingTool(pen.type.ink, color: UIColor(argb: pen.inkColor), width: InkWidth.toolWidth(pen.size, pen.type.ink))
      case .eraser:
        // Whole strokes, or precise (rubs out just what it passes over), at her size.
        if parent.eraser.precise {
          canvas.tool = PKEraserTool(.bitmap, width: CGFloat(parent.eraser.size))
        } else {
          canvas.tool = PKEraserTool(.vector, width: CGFloat(parent.eraser.size))
        }
      case .lasso, .shape:
        // Our own lasso and Shapes tool (Android's): the canvas doesn't draw while they're in use.
        canvas.tool = PKInkingTool(.monoline, color: .clear, width: 1)
      }
    }

    func run(_ cmd: CanvasCommand) {
      guard let canvas else { return }
      switch cmd {
      case .undo: canvas.undoManager?.undo()
      case .redo: canvas.undoManager?.redo()
      case .addPage:
        pageCount += 1
        updateContent()
        persistPages()
      case .newText: startNewText()
      case .copySelection: copySelection()
      case .cutSelection: cutSelection()
      case .duplicateSelection: duplicateSelection()
      case .deleteSelection: deleteSelection()
      case .boxSelection: boxSelection()
      case .paste: pasteAtOffer()
      case .recolourSelection(let c): recolourSelection(c)
      case .thickenSelection(let v): thickenSelection(v)
      case .mirrorSelection(let h): mirrorSelection(horizontal: h)
      case .arrangeSelection(let f): arrangeSelection(toFront: f)
      case .deletePage(let i): deletePage(i)
      case .goToPage(let i):
        let target = min(max(i, 0), pageCount - 1)
        let r = layout.rect(target)
        let y = CGFloat(r.top) * canvas.zoomScale - canvas.contentInset.top
        canvas.setContentOffset(CGPoint(x: canvas.contentOffset.x, y: y), animated: true)
      case .fitZoom:
        guard let pages else { break }
        let fit = min((canvas.bounds.width - 48) / pages.worldSize.width, 1.2)
        canvas.setZoomScale(fit, animated: true)
      }
      reportUndo()
    }

    func reportUndo() {
      // After the current view update: this is also called while the canvas is being made (loading),
      // where a change to the screen's state would be dropped (a 2-page PDF showed "1 / 1").
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        let u = self.canvas?.undoManager
        self.parent.onUndoState(u?.canUndo ?? false, u?.canRedo ?? false)
        self.parent.onPageCount(self.pageCount)
      }
    }

    // MARK: Size and zoom

    func updateContent() {
      guard let canvas, let pages else { return }
      pages.pages.count = pageCount
      let world = pages.worldSize
      let z = canvas.zoomScale
      pages.layer.anchorPoint = .zero
      pages.bounds = CGRect(origin: .zero, size: world)
      pages.transform = CGAffineTransform(scaleX: z, y: z)
      pages.layer.position = .zero
      pages.setNeedsDisplay()
      canvas.contentSize = CGSize(width: world.width * z, height: (world.height + 300) * z)
      // Until she zooms by hand, the page keeps fitting the canvas as its size settles (the screen
      // slides in, the device turns): set once early, the fit was lost.
      if didFit, !zoomedByHand, canvas.bounds.size != fittedSize, canvas.bounds.width > 0 {
        fittedSize = canvas.bounds.size
        DispatchQueue.main.async { [weak self] in self?.fitWidth() }
      }
      if !didFit, canvas.bounds.width > 0 {
        didFit = true
        fittedSize = canvas.bounds.size
        // The page's whole width on screen (a slide-shaped PDF page is far wider than A4), once the
        // canvas has its size.
        DispatchQueue.main.async { [weak self] in self?.fitWidth() }
        return
      }
      centre()
    }

    /// She pinched: the first fit doesn't come back over it.
    var zoomedByHand = false
    var fittedSize: CGSize = .zero

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
      if scrollView.isTracking || scrollView.isZoomBouncing || scrollView.pinchGestureRecognizer?.state == .began { zoomedByHand = true }
    }

    /// The first page's whole width on screen, from the top of the first page.
    private func fitWidth() {
      guard let canvas, let pages else { return }
      // It opens where she left off (Android keeps the view per notebook); the first time, the page's width.
      let saved = parent.notebook.viewport.flatMap { v -> Viewport? in v.zoom > 0.05 ? v : nil }
      let fit = min((canvas.bounds.width - 48) / pages.worldSize.width, 1.2)
      let zoom = saved.map { min(max(CGFloat($0.zoom), canvas.minimumZoomScale), canvas.maximumZoomScale) } ?? fit
      // Animated: PKCanvasView ignored the plain zoom change here (the zoom chip's animated one works).
      canvas.setZoomScale(zoom, animated: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        guard let self, let canvas = self.canvas else { return }
        self.updateContent()
        let z = canvas.zoomScale
        let at = saved.map { CGPoint(x: CGFloat($0.x) * z - canvas.contentInset.left, y: CGFloat($0.y) * z - canvas.contentInset.top) }
          ?? CGPoint(x: -canvas.contentInset.left, y: -canvas.contentInset.top)
        canvas.setContentOffset(at, animated: false)
        self.reportView()
      }
    }

    private func centre() {
      guard let canvas, let pages else { return }
      let w = pages.worldSize.width * canvas.zoomScale
      let side = max((canvas.bounds.width - w) / 2, 16)
      canvas.contentInset = UIEdgeInsets(top: parent.topClearance, left: side, bottom: 40, right: side)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      updateContent()
      layoutTextEditor()
      redrawSelection()
      reportView()
    }

    /// Which page is in the middle of the screen, and the zoom.
    private func reportView() {
      guard let canvas else { return }
      let z = max(canvas.zoomScale, 0.01)
      let midY = (canvas.contentOffset.y + canvas.bounds.height / 2) / z
      let p = min(max(layout.indexAt(Float(midY)), 0), max(pageCount - 1, 0))
      parent.onView(p, z)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { updateContent() }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      reportView()
      reportSelection()
    }

    // MARK: Keeping the store in step

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
      guard !loading else { return }
      sync(canvasView.drawing)
      reportUndo()
    }

    /// Matches the drawing's strokes to what's stored: new ones are stored, moved ones rewritten,
    /// missing ones removed. Only ink rows are touched; shapes, pictures and text stay as they are.
    func sync(_ drawing: PKDrawing) {
      var byKey: [StrokeKey: [Int]] = [:]
      for (i, s) in stored.enumerated() { byKey[s.key, default: []].append(i) }
      var next: [(key: StrokeKey, stroke: InkStroke)] = []
      var used = Set<Int>()
      var changed: [InkStroke] = []
      var rebuilt: [PKStroke] = []
      var needsRebuild = false
      let pen = currentPen
      var z = max(stored.map(\.stroke.z).max() ?? 0, shapeZ) + 1
      for pk in drawing.strokes {
        let key = StrokeKey(pk)
        if let i = byKey[key]?.first(where: { !used.contains($0) }) {
          used.insert(i)
          var s = stored[i].stroke
          if pk.transform != .identity {
            // Moved or resized with the lasso: store the moved points, and draw it untransformed.
            s = InkStroke.from(pk, pen: PenSlot(id: "", type: s.pen, color: s.color, size: s.size), id: s.id, z: s.z)
            s.size = Float(CGFloat(s.size) * sqrt(abs(pk.transform.a * pk.transform.d - pk.transform.b * pk.transform.c)))
            changed.append(s)
            let fresh = s.pkStroke(mask: mask(for: s))
            rebuilt.append(fresh)
            next.append((StrokeKey(fresh), s))
            needsRebuild = true
          } else {
            rebuilt.append(pk)
            next.append((key, s))
          }
        } else if let given = pending.removeValue(forKey: key) ?? archive[key] {
          // A copy we put there ourselves (duplicate, paste, a box): it keeps its own pen.
          var s = given
          s.z = z
          z += 1
          changed.append(s)
          growPages(for: s)
          rebuilt.append(pk)
          next.append((key, s))
        } else if isSnappedStroke(pk) || parent.tool == .lasso || parent.tool == .shape {
          // The stroke that became a shape (hold-to-shape), or one PencilKit drew while the lasso was
          // on (in clear ink): neither is kept.
          needsRebuild = true
        } else {
          // A new stroke from the pen.
          let s = InkStroke.from(pk, pen: pen, id: newId(), z: z)
          if !pen.type.pressureSensitive, pk.path.count > 2 {
            // Keep the live width matching the stored one (see InkWidth).
            let mid = pk.path[pk.path.count / 2]
            InkWidth.learn(pen.type.ink, size: pen.size, pointSize: mid.size.width, secondary: mid.secondaryScale)
          }
          z += 1
          changed.append(s)
          growPages(for: s)
          let m = mask(for: s)
          if let m, !m.bounds.contains(CGRect(s.bounds)) {
            // It runs off its page: draw it hidden past the edge, as it will be from now on.
            var masked = pk
            masked.mask = m
            rebuilt.append(masked)
            next.append((StrokeKey(masked), s))
            needsRebuild = true
          } else {
            rebuilt.append(pk)
            next.append((key, s))
          }
        }
      }
      // A stroke replaced under the same id (recoloured, mirrored) isn't removed.
      let keptIds = Set(next.map(\.stroke.id))
      let removed = stored.indices.filter { !used.contains($0) }.map { stored[$0].stroke.id }.filter { !keptIds.contains($0) }
      // Every stroke seen, so one brought back by undo is stored exactly as it was (not with the pen in use).
      for (k, st) in stored { archive[k] = st }
      stored = next
      do {
        for s in changed { try parent.db.put(s.row, in: parent.notebook.id) }
        for id in removed { try parent.db.removeItem(id) }
      } catch {
        CrashNote.log("saving strokes: \(error)")
      }
      if !changed.isEmpty || !removed.isEmpty { touch() }
      if needsRebuild, let canvas {
        // Swap in the stored form (page mask, untransformed) without making an undo step of it.
        loading = true
        canvas.undoManager?.disableUndoRegistration()
        canvas.drawing = PKDrawing(strokes: rebuilt)
        canvas.undoManager?.enableUndoRegistration()
        loading = false
      }
    }

    var currentPen: PenSlot {
      if case .pen(let id) = parent.tool, let p = parent.pens.first(where: { $0.id == id }) { return p }
      return PenSlot.defaults[0]
    }

    /// Writing on the last page adds another below it, as pages "keep coming as you write".
    private func growPages(for s: InkStroke) {
      guard paged, let b = s.inputs.bounds else { return }
      let need = layout.needed(b)
      if need > pageCount {
        pageCount = need
        updateContent()
        persistPages()
      }
    }

    func persistPages() {
      try? parent.db.run("UPDATE notebooks SET pages=? WHERE id=?", [.int(Int64(pageCount)), .text(parent.notebook.id)])
    }

    func touch() {
      saveWork?.cancel()
      let id = parent.notebook.id, db = parent.db
      let w = DispatchWorkItem { try? db.run("UPDATE notebooks SET updated=? WHERE id=?", [.int(nowMillis()), .text(id)]) }
      saveWork = w
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    func saveNow() {
      saveWork?.perform()
      saveWork = nil
      guard let canvas else { return }
      let vp = Viewport(
        x: Float((canvas.contentOffset.x + canvas.contentInset.left) / canvas.zoomScale),
        y: Float((canvas.contentOffset.y + canvas.contentInset.top) / canvas.zoomScale), zoom: Float(canvas.zoomScale))
      if let json = try? String(data: JSONEncoder().encode(vp), encoding: .utf8) {
        try? parent.db.run("UPDATE notebooks SET viewport=? WHERE id=?", [.text(json), .text(parent.notebook.id)])
      }
      saveThumbnail()
    }

    /// The library card's preview: the top of page 1, or the writing last seen on an endless canvas.
    private func saveThumbnail() {
      guard let canvas, let pages else { return }
      let region: CGRect
      if paged {
        region = Thumbnail.previewRegion(CGRect(layout.rect(0)))
      } else {
        let z = max(canvas.zoomScale, 0.01)
        let visible = CGRect(x: canvas.contentOffset.x / z, y: canvas.contentOffset.y / z, width: canvas.bounds.width / z, height: canvas.bounds.height / z)
        let seen = canvas.drawing.bounds.intersection(visible)
        let around = seen.isNull || seen.isEmpty ? visible : seen.insetBy(dx: -48, dy: -48)
        var w = max(around.width, around.height * Thumbnail.cardAspect, 560)
        w = min(w, visible.width * 1.5)
        let h = w / Thumbnail.cardAspect
        region = CGRect(x: around.midX - w / 2, y: around.midY - h / 2, width: w, height: h)
      }
      Thumbnail.save(id: parent.notebook.id, region: region, pages: pages.pages, drawing: canvas.drawing, db: parent.db)
    }
  }
}

enum CanvasCommand: Equatable {
  case undo, redo, addPage, fitZoom, newText
  case copySelection, cutSelection, duplicateSelection, deleteSelection, boxSelection, paste
  case recolourSelection(UInt32), thickenSelection(Float), mirrorSelection(Bool), arrangeSelection(Bool)
  case deletePage(Int)
  case goToPage(Int)
}

/// The eraser as she set it in its panel.
struct EraserSettings: Equatable {
  var precise = false
  var size: Float = 20
}

/// A plain log of things that went wrong, kept on the device (Android's CrashLog, simplified).
enum CrashNote {
  static func log(_ text: String) {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("crash.log")
    let line = "\(Date()) \(text)\n"
    if let h = try? FileHandle(forWritingTo: url) {
      h.seekToEndOfFile()
      h.write(Data(line.utf8))
      try? h.close()
    } else {
      try? Data(line.utf8).write(to: url)
    }
  }
}

/// An imported PDF's page drawn from the PDF kept beside its picture (Android's `SharpPdf` draws
/// patches at screen resolution; here the tiled page layer simply draws the page as vectors at every
/// zoom). The picture's name says which PDF and page it is: `pdf-<pdf>-p<page>-<uuid>.jpg`.
final class SharpPage: @unchecked Sendable {
  private let page: PDFPage
  /// PDFKit isn't safe to draw from several tile threads at once.
  private static let lock = NSLock()
  nonisolated(unsafe) private static var docs: [String: PDFDocument] = [:]

  private init(_ page: PDFPage) { self.page = page }

  /// The page a picture item shows, when it's an imported PDF page whose PDF is here.
  static func of(_ row: ItemRow) -> (id: String, rect: CGRect, page: SharpPage)? {
    guard let p = PictureRow(row), p.crop == nil, let (id, index) = p.pdfSource, p.rect.width > 0, p.rect.height > 0 else { return nil }
    lock.lock()
    defer { lock.unlock() }
    let doc: PDFDocument
    if let d = docs[id] {
      doc = d
    } else {
      guard let d = PDFDocument(url: AppFiles.folders.images.appendingPathComponent("pdf-\(id).pdf")) else { return nil }
      docs[id] = d
      doc = d
    }
    guard let page = doc.page(at: index) else { return nil }
    return (row.id, CGRect(p.rect), SharpPage(page))
  }

  /// Draws the page filling [rect] (world units, y down) on white.
  func draw(in rect: CGRect, _ cg: CGContext) {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let box = page.bounds(for: .mediaBox)
    let turned = page.rotation % 180 != 0
    let w = turned ? box.height : box.width
    guard w > 0 else { return }
    cg.saveGState()
    cg.setFillColor(UIColor.white.cgColor)
    cg.fill(rect)
    cg.clip(to: rect)
    let s = rect.width / w
    cg.translateBy(x: rect.minX, y: rect.maxY)
    cg.scaleBy(x: s, y: -s)
    page.draw(with: .mediaBox, to: cg)
    cg.restoreGState()
  }
}
