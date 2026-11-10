import ImageIO
import PencilKit
import SwiftUI
import TaliCore
import UIKit

/// The tool in use (the parts ported so far).
enum Tool: Equatable {
  case pen(String)  // a PenSlot id
  case eraser
  case lasso
}

/// What the page layer draws besides paper: shapes and pictures from the notebook (pictures first,
/// then shapes, all under the writing for now).
struct UnderItems: @unchecked Sendable {
  var shapes: [ShapeRow] = []
  var pictures: [(rect: CGRect, image: CGImage)] = []
}

/// Paper, pictures and shapes for the page column, drawn in tiles off the main thread so they stay
/// sharp at any zoom. Everything it reads is set from the main thread before it's asked to draw.
final class PagesLayer: CATiledLayer, @unchecked Sendable {
  nonisolated(unsafe) var layout = Pages.portrait
  nonisolated(unsafe) var count = 1
  nonisolated(unsafe) var paper = PaperStyle.GRID
  nonisolated(unsafe) var dark = false
  nonisolated(unsafe) var under = UnderItems()

  override class func fadeDuration() -> CFTimeInterval { 0.08 }

  var worldSize: CGSize { CGSize(width: CGFloat(layout.width), height: CGFloat(layout.rect(max(count, 1) - 1).bottom)) }

  override func draw(in cg: CGContext) {
    let rect = cg.boundingBoxOfClipPath
    let scale = max(cg.ctm.a / max(contentsScale, 1), 0.01)
    for i in 0..<max(count, 1) {
      let page = CGRect(layout.rect(i))
      guard page.intersects(rect) else { continue }
      PaperPainter.draw(paper, page: page, in: cg, scale: scale, dark: dark)
    }
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
  var onUndoState: (Bool, Bool) -> Void
  var onPageCount: (Int) -> Void
  @Binding var command: CanvasCommand?

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> PKCanvasView {
    let c = context.coordinator
    let v = PKCanvasView()
    v.delegate = c
    v.drawingPolicy = .pencilOnly
    if ProcessInfo.processInfo.arguments.contains("-uitest") { v.drawingPolicy = .anyInput }
    v.backgroundColor = .clear
    v.isOpaque = false
    v.minimumZoomScale = 0.3
    v.maximumZoomScale = 6
    v.showsVerticalScrollIndicator = false
    v.showsHorizontalScrollIndicator = false
    v.contentInsetAdjustmentBehavior = .never
    v.alwaysBounceVertical = true
    let pages = PagesView(frame: .zero)
    pages.pages.layout = notebook.pageLayout
    pages.pages.paper = notebook.paper
    pages.pages.dark = notebook.dark
    v.insertSubview(pages, at: 0)
    c.canvas = v
    c.pages = pages
    c.load()
    return v
  }

  func updateUIView(_ v: PKCanvasView, context: Context) {
    let c = context.coordinator
    c.parent = self
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
    private var stored: [(key: StrokeKey, stroke: InkStroke)] = []
    private var pageCount = 1
    private var loading = false
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

    private var layout: Pages { parent.notebook.pageLayout }
    private var paged: Bool { parent.notebook.pages != nil }

    /// The page a stroke belongs to (where it began), as a PencilKit mask.
    private func mask(for s: InkStroke) -> UIBezierPath? {
      guard paged, let first = s.inputs.points.first else { return nil }
      guard let r = layout.clip(anchorY: first.y, count: pageCount, between: false) else { return nil }
      return UIBezierPath(rect: CGRect(x: CGFloat(r.left), y: CGFloat(r.top), width: CGFloat(r.width), height: CGFloat(r.height)))
    }

    func load() {
      guard let canvas else { return }
      loading = true
      let rows = (try? parent.db.items(of: parent.notebook.id)) ?? []
      var strokes: [PKStroke] = []
      stored = []
      var under = UnderItems()
      for row in rows {
        if let shape = ShapeRow(row) {
          under.shapes.append(shape)
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

    func applyTool() {
      guard let canvas else { return }
      switch parent.tool {
      case .pen(let id):
        let pen = parent.pens.first { $0.id == id } ?? PenSlot.defaults[0]
        canvas.tool = PKInkingTool(pen.type.ink, color: UIColor(argb: pen.inkColor), width: CGFloat(pen.size))
      case .eraser:
        canvas.tool = PKEraserTool(.vector)
      case .lasso:
        canvas.tool = PKLassoTool()
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
      }
      reportUndo()
    }

    private func reportUndo() {
      let u = canvas?.undoManager
      parent.onUndoState(u?.canUndo ?? false, u?.canRedo ?? false)
      parent.onPageCount(pageCount)
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
      if !didFit, canvas.bounds.width > 0 {
        didFit = true
        let fit = min((canvas.bounds.width - 48) / world.width, 1.2)
        canvas.zoomScale = fit
      }
      centre()
    }

    private func centre() {
      guard let canvas, let pages else { return }
      let w = pages.worldSize.width * canvas.zoomScale
      let side = max((canvas.bounds.width - w) / 2, 16)
      canvas.contentInset = UIEdgeInsets(top: 104, left: side, bottom: 40, right: side)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { updateContent() }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { updateContent() }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      if !didFit { updateContent() }
    }

    // MARK: Keeping the store in step

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
      guard !loading else { return }
      sync(canvasView.drawing)
      reportUndo()
    }

    /// Matches the drawing's strokes to what's stored: new ones are stored, moved ones rewritten,
    /// missing ones removed. Only ink rows are touched; shapes, pictures and text stay as they are.
    private func sync(_ drawing: PKDrawing) {
      var byKey: [StrokeKey: [Int]] = [:]
      for (i, s) in stored.enumerated() { byKey[s.key, default: []].append(i) }
      var next: [(key: StrokeKey, stroke: InkStroke)] = []
      var used = Set<Int>()
      var changed: [InkStroke] = []
      var rebuilt: [PKStroke] = []
      var needsRebuild = false
      let pen = currentPen
      var z = (stored.map(\.stroke.z).max() ?? 0) + 1
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
        } else {
          // A new stroke from the pen.
          let s = InkStroke.from(pk, pen: pen, id: newId(), z: z)
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
      let removed = stored.indices.filter { !used.contains($0) }.map { stored[$0].stroke.id }
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

    private var currentPen: PenSlot {
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

    private func persistPages() {
      try? parent.db.run("UPDATE notebooks SET pages=? WHERE id=?", [.int(Int64(pageCount)), .text(parent.notebook.id)])
    }

    private func touch() {
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
    }
  }
}

enum CanvasCommand: Equatable {
  case undo, redo, addPage
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

/// A picture item (kind 2): where it sits and its image, read from the app's images folder at a
/// size that suits the page (a PDF page or photo is never decoded at full size).
func picture(from row: ItemRow) -> (rect: CGRect, image: CGImage)? {
  guard let obj = try? JSONSerialization.jsonObject(with: row.payload) as? [String: Any], let file = obj["file"] as? String,
    let r = obj["rect"] as? [String: Any]
  else { return nil }
  func n(_ k: String) -> CGFloat { CGFloat((r[k] as? NSNumber)?.doubleValue ?? 0) }
  let rect = CGRect(x: n("left"), y: n("top"), width: n("right") - n("left"), height: n("bottom") - n("top"))
  guard !file.contains("/"), rect.width > 0, rect.height > 0 else { return nil }
  let url = AppFiles.folders.images.appendingPathComponent(file)
  guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  let maxSide = min(max(rect.width, rect.height) * 2, 2400)
  let opts: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxSide,
    kCGImageSourceCreateThumbnailWithTransform: true,
  ]
  guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
  return (rect, image)
}
